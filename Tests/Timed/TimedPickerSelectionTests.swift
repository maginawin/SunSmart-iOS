import Foundation

final class Node: Equatable {
    let primaryUnicastAddress: Int
    var schedulerModel: Int? = 1
    var state = true, isKeybindComplete = true
    init(_ address: Int) { primaryUnicastAddress = address }
    static func == (lhs: Node, rhs: Node) -> Bool { lhs === rhs }
}
final class Group {}
final class Scene {}
final class Schedule {}
final class MeshNetworkManager {
    static let instance = MeshNetworkManager()
    var realNodes: [Node] = [], groups: [Group] = [], scenes: [Scene] = []
}
final class ScheduleAddTargetView {}
enum ScheduleTarget { case devices([Node]), groups([Group]), scene(Scene?) }
final class UIButton { var isSelected = false }
final class Collection { func reloadData() {} }
extension String { var localizedString: String { self } }
enum XWHUDManager { static func showTipHUD(_ message: String, isLineFeed: Bool) {} }
final class EditorView { var isSyncCompletion = true }
enum NodeSyncStatusRefresh {
    static var callbacks: [(Bool) -> Void] = []
    static func request(schedule: Schedule, owner: AnyObject, completion: @escaping (Bool) -> Void) { callbacks.append(completion) }
    static func cancel(owner: AnyObject) {}
}
final class ScheduleTargetDisplayState {
    var requests = 0
    var callback: (() -> Void)?
    func refresh(schedule: Schedule, didUpdate: @escaping () -> Void) { requests += 1; callback = didUpdate }
}

final class ScheduleAddViewController {
    var schedule: Schedule? = Schedule()
    var syncRequestID = UUID(), isDisplaying = true
    let scheduleAddView = EditorView()
    var result: ScheduleTarget?
    func updateScheduleTarget(_ target: ScheduleTarget) { result = target }
    // PRODUCTION_SELECTION
    // PRODUCTION_EDITOR_REFRESH
    // PRODUCTION_EDITOR_HIDE
}

final class ScheduleDevicesView {
    static var shown: ScheduleDevicesView!
    let nodes: [Node], schedule: Schedule?
    var selectNodes: [Node], visibleNodes: [Node], disableUnselectNodes: [Node] = []
    let selectCallback: (([Node]) -> Void)?
    let collectionView = Collection()
    var hidden = false
    var isShowing = true, superview: NSObject? = NSObject()
    let syncDisplay = ScheduleTargetDisplayState()
    var iconUpdates = 0
    func refreshVisibleSyncStatus() { iconUpdates += 1 }
    init(nodes: [Node], selectNodes: [Node], schedule: Schedule?, selectBack: (([Node]) -> Void)?) {
        self.nodes = nodes; self.selectNodes = selectNodes; visibleNodes = nodes
        self.schedule = schedule; selectCallback = selectBack
    }
    func show() { Self.shown = self; checkOffline() }
    func hide() { hidden = true }
    func updateSelectAllState() {}
    // PRODUCTION_OFFLINE
    // PRODUCTION_SELECT_ALL
    // PRODUCTION_FINISH
    // PRODUCTION_PICKER_REFRESH
}
final class ScheduleGroupsView {
    init(groups: [Group], selectGroups: [Group], schedule: Schedule?, selectBack: (([Group]) -> Void)?) {}
    func show() {}
}
final class ScheduleScenesView {
    init(scenes: [Scene], selectScene: Scene?, schedule: Schedule?, selectBack: ((Scene?) -> Void)?) {}
    func show() {}
}

let manager = MeshNetworkManager.instance
manager.realNodes = (0..<487).map(Node.init)
let selected = manager.realNodes[0], hiddenSelected = manager.realNodes[1], offline = manager.realNodes[2]
offline.state = false
manager.realNodes[486].schedulerModel = nil
let controller = ScheduleAddViewController()
for input in [[Node](), [selected], [selected, hiddenSelected, offline]] {
    controller.view(ScheduleAddTargetView(), didClickTargetAction: .devices(input))
    let picker = ScheduleDevicesView.shown!
    precondition(picker.nodes.count == 486 && picker.selectNodes == input)
    precondition(picker.disableUnselectNodes == input.filter { !$0.state })
    controller.result = nil
    picker.cancelBtnAction()
    precondition(picker.hidden && controller.result == nil)
}
controller.view(ScheduleAddTargetView(), didClickTargetAction: .devices([selected, hiddenSelected, offline]))
let picker = ScheduleDevicesView.shown!
picker.visibleNodes = [selected]
let button = UIButton(); button.isSelected = true
picker.selectAllBtnAction(sender: button)
precondition(picker.selectNodes == [hiddenSelected, offline], "filtered Select All lost hidden/protected selection")
picker.confirmBtnAction()
guard case .devices(let returned) = controller.result else { fatalError("Confirm did not return selection") }
precondition(returned == [hiddenSelected, offline])
controller.schedule = nil
controller.view(ScheduleAddTargetView(), didClickTargetAction: .devices([selected, offline]))
precondition(ScheduleDevicesView.shown.selectNodes == [selected], "new schedule retained offline selection")
controller.schedule = Schedule()
controller.refreshSyncStatus()
let stale = NodeSyncStatusRefresh.callbacks.last!
controller.refreshSyncStatus()
stale(false)
precondition(!controller.scheduleAddView.isSyncCompletion, "old read overwrote pending editor")
let latest = NodeSyncStatusRefresh.callbacks.last!
latest(false)
precondition(controller.scheduleAddView.isSyncCompletion)
controller.viewWillDisappear(false)
latest(true)
precondition(controller.scheduleAddView.isSyncCompletion, "hidden editor received a late update")
picker.refreshSyncStatus()
let iconUpdates = picker.iconUpdates, requests = picker.syncDisplay.requests
picker.isShowing = false // Closing animation still leaves superview attached.
picker.syncDisplay.callback?()
picker.refreshSyncStatus()
precondition(picker.iconUpdates == iconUpdates && picker.syncDisplay.requests == requests,
             "closing picker accepted a callback or scheduled another read")
print("PASS: production Devices picker preserves 0/1/multiple selections, offline protection, filtered deselection, Confirm and Cancel")
print("PASS: production editor rejects replaced/hidden callbacks; closing picker ignores callbacks and new status requests")
