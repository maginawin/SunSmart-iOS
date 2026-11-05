import Foundation
class View { var window: View? }
class UIViewController {
    let view = View()
    var viewIfLoaded: View? { view }
    func viewDidAppear(_ animated: Bool) {}
}
class Collection {
    var firstShowFlashScrollIndicators = false
    func flashScrollIndicatorsIfNeeded() {}
}
class MeshLibManager {
    static let manager = MeshLibManager()
    var isMeshNetworkConnected = true
    var scans = 0
    weak var messageDelegate: AnyObject?
    func register(_ owner: AnyObject) {}
    func refreshNodesRSSI(withWaitFor: Int, finished: (() -> Void)?) { scans += 1 }
}
class MeshNodeHeartbeatManager {
    static let shared = MeshNodeHeartbeatManager()
    var manual = 0, recovery = 0
    func refresh() { manual += 1 }
    func refreshOfflineNodes() { recovery += 1 }
}
final class Lights: UIViewController {
    var isPageVisible = false
    var needsNodeStateRefresh = false
    let collectionView = Collection()
    func refreshAllControlCooldown() {}
    // PRODUCTION
}
let page = Lights(), heartbeat = MeshNodeHeartbeatManager.shared
page.view.window = View()
page.viewDidAppear(false)
guard heartbeat.recovery == 1 else {
    print("FAIL: returning to Lights without a pending flag must request shared presence recovery")
    exit(1)
}
precondition(heartbeat.manual == 0 && MeshLibManager.manager.scans == 0,
             "automatic presence recovery must not invoke manual refresh or RSSI scan")
page.getNodesState()
precondition(heartbeat.manual == 1 && MeshLibManager.manager.scans == 1)
page.isPageVisible = false
page.getNodesState()
precondition(heartbeat.manual == 1 && page.needsNodeStateRefresh)
page.viewDidAppear(false)
precondition(heartbeat.manual == 2 && !page.needsNodeStateRefresh)
page.view.window = nil
let count = heartbeat.recovery
page.viewDidAppear(false)
precondition(heartbeat.recovery == count, "detached page cannot request recovery")
print("PASS: visible return recovers without pending flag/RSSI; manual and hidden pending behavior preserved")
