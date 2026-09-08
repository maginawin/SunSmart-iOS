// 可控 UI 事件队列：测试可以在排队与执行之间插入 STOP 或新轮次。
final class DispatchQueue {
    static let main = DispatchQueue()
    var pending: [() -> Void] = []
    func async(execute: @escaping () -> Void) { pending.append(execute) }
    func drain() { while !pending.isEmpty { pending.removeFirst()() } }
}
enum SyncState { case inSync, syncFailure, syncSuccess }
enum ModelState { case failed, successful, wait }
final class TestModel { var isFineshed = false; var state = ModelState.successful }
struct TestSection { let allModels: [TestModel] }
final class TestTable { var reloads = 0; func reloadData() { reloads += 1 } }
final class TestButton {}
final class TestNavigation {
    func hideAutomaticHud() {}
    func popToViewController(vcClass: AnyClass) {}
}
final class BleFirmwareUpdateViewController: NSObject {}
final class SyncDevicesProgressView {
    static func current() -> SyncDevicesProgressView? { nil }
    func hide() {}
    func reload() {}
}
enum SpaceChangeDataType { case device }
let spaceDataChangedNotificaitonName = "sync-run-completion-test"

struct SyncTaskPlanResult {
    let sections: [TestSection]
    let initialState: SyncState
    let proximityLightingTasks: [TestModel]
    let failureMessages: [String]
}
enum XWHUDManager {
    static var hides = 0
    static var errors: [String] = []
    static func hideInView(with view: Int) { hides += 1 }
    static func showErrorTipHUD(_ message: String) { errors.append(message) }
}
