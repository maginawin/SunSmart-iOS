// Runs the controller's actual refresh/lifecycle methods with UI and Mesh doubles.
// This verifies scheduling, not UIKit appearance propagation or BLE behavior.
import Foundation
class UIViewController {
    var viewIfLoaded: View? = View()
    func viewDidAppear(_ animated: Bool) {}
    func viewWillDisappear(_ animated: Bool) {}
}
final class View { var window: Bool? = true }
final class CollectionView {
    var firstShowFlashScrollIndicators = false
    func flashScrollIndicatorsIfNeeded() {}
}
enum CBManagerState { case poweredOn, poweredOff }
final class MeshNetworkManager {}
protocol Bearer {}
struct TestBearer: Bearer {}
final class MeshLibManager {
    static let manager = MeshLibManager()
    var isMeshNetworkConnected = true
    var messageDelegate: AnyObject?
    var refreshCount = 0
    func register(_ owner: AnyObject) {}
    func refreshNodesRSSI(withWaitFor: TimeInterval, finished: (() -> Void)?) {
        refreshCount += 1
    }
}
final class MeshNodeHeartbeatManager {
    static let shared = MeshNodeHeartbeatManager()
    var autoHeartbeatLoop = true
    var refreshCount = 0
    func refresh() { refreshCount += 1 }
}

// PRODUCTION_CONTROLLER_METHODS

@main
struct DeviceLightsStateRefreshTests {
    static func main() {
        let controller = DeviceLightsViewController()
        let manager = MeshLibManager.manager
        let model = MeshNetworkManager()
        let bearer = TestBearer()
        for _ in 0..<6 { controller.getNodesState() }
        precondition(manager.refreshCount == 0, "Hidden page must not scan after add notifications")
        controller.viewDidAppear(false)
        precondition(manager.refreshCount == 1, "Returning consumes one coalesced refresh")
        controller.viewDidAppear(false)
        precondition(manager.refreshCount == 1)
        controller.viewWillDisappear(false)
        controller.getNodesState()
        controller.meshNetworkManager(bluetoothDidUpdateState: .poweredOn)
        controller.meshNetworkManager(model, bearerDidOpen: bearer)
        precondition(manager.refreshCount == 1, "Hidden callbacks must not steal the Add Device scanner")
        manager.isMeshNetworkConnected = false
        controller.viewDidAppear(false)
        precondition(manager.refreshCount == 1)
        manager.isMeshNetworkConnected = true
        controller.meshNetworkManager(model, bearerDidOpen: bearer)
        precondition(manager.refreshCount == 2, "Reconnect must consume pending refresh even with automatic heartbeat")
        controller.meshNetworkManager(model, bearerDidOpen: bearer)
        precondition(manager.refreshCount == 2)
        controller.viewIfLoaded?.window = nil
        controller.getNodesState()
        precondition(manager.refreshCount == 2)
        controller.viewIfLoaded?.window = true
        controller.viewDidAppear(false)
        precondition(manager.refreshCount == 3)
        controller.getNodesState()
        precondition(manager.refreshCount == 4, "Visible manual refresh still works")
        precondition(MeshNodeHeartbeatManager.shared.refreshCount == 4)
        print("DeviceLightsStateRefreshTests passed: hidden/coalesced/return/reconnect/manual refresh")
    }
}
