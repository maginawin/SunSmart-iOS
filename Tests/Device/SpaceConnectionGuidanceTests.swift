// Isolated boundaries for production methods inserted by the regression runner.
import Foundation
import CoreGraphics

final class Layer { var cornerRadius: CGFloat = 0 }
final class View {
    let layer = Layer()
    var subviews: [WYProgressHUD] = []
}
class UIViewController: NSObject {
    var view: View! = View()
    var wm_pageController: UIViewController?
    func willMove(toParent parent: UIViewController?) {}
    func viewDidDisappear(_ animated: Bool) {}
}
final class Label { var text: String? }
final class WYProgressHUD {
    let bezelView = View()
    let detailsLabel = Label()
    var minSize = CGSize.zero
    var finished = false
    weak var host: View?
    var closeAction: (() -> Void)?
    static func forView(_ view: View) -> WYProgressHUD? {
        view.subviews.reversed().first { !$0.finished }
    }
    func addCloseButton(closeCallback: (() -> Void)?) { closeAction = closeCallback }
    func hide(animated: Bool) {
        finished = true
        host?.subviews.removeAll { $0 === self }
    }
    func tapClose() {
        // ProgressHUD+Extension invokes the owner callback before hiding itself.
        closeAction?()
        hide(animated: true)
    }
}
enum XWHUDManager {
    static let window = View()
    static var currentView = View()
    static func showGifImagesHUD(in view: View, gifFileName: String, message: String,
                                 timer: Double, margin: CGFloat) {
        let hud = WYProgressHUD()
        hud.host = view
        view.subviews.append(hud)
    }
    static func currentHUD() -> WYProgressHUD? {
        WYProgressHUD.forView(window) ?? WYProgressHUD.forView(currentView)
    }
    static func isVisible() -> Bool { currentHUD() != nil }
    static func hideInView(with view: View) { WYProgressHUD.forView(view)?.hide(animated: true) }
    static func hide() {
        hideInView(with: window)
        hideInView(with: currentView)
    }
}
final class Space { var applyDeviceAddressCount: Int? }
final class MeshLibManager {
    static let manager = MeshLibManager()
    var isMeshNetworkConnected = true
}
final class SpaceDebugUARTManager {
    static let shared = SpaceDebugUARTManager()
    func setActiveSpace(_ space: Space) {}
    func evaluateCurrentProxy(space: Space) {}
}
let isIPad = false
let SCREEN_WIDTH: CGFloat = 390

final class DevicesViewController: UIViewController {
    var connectLoadingHUD: WYProgressHUD?
    var guidanceTimer: Timer?
    var firstConnectionNetwork = true
    let space = Space()
    var addressPrompts = 0
    func getNextGuidanceMessage() -> String? { "Guidance" }
    func applyDeviceAddressAlert() { addressPrompts += 1 }
    // PRODUCTION_METHODS
}

func check(_ condition: Bool, _ message: String) {
    if !condition { print("FAIL: \(message)"); exit(1) }
}
func page(_ parent: UIViewController) -> DevicesViewController {
    let page = DevicesViewController()
    page.wm_pageController = parent
    XWHUDManager.currentView = parent.view
    page.showConnectionGuidance()
    return page
}

let parent = UIViewController()
let oldPage = page(parent)
let oldHUD = oldPage.connectLoadingHUD!
let oldTimer = oldPage.guidanceTimer!
oldPage.space.applyDeviceAddressCount = 1
// WMPageController.reloadData calls willMove(nil), even before appearance completes.
oldPage.willMove(toParent: nil)
check(!XWHUDManager.isVisible(), "pagination removal left an unfinished HUD")
check(oldHUD.finished && !oldTimer.isValid, "pagination removal did not end HUD and timer")
let newPage = page(parent)
let newHUD = newPage.connectLoadingHUD!
oldPage.viewDidDisappear(false)
check(!newHUD.finished, "late old-page cleanup dismissed replacement HUD")
newPage.space.applyDeviceAddressCount = 1
newHUD.tapClose()
check(!XWHUDManager.isVisible(), "menu remains blocked after closing replacement HUD")
check(newPage.connectLoadingHUD == nil && newPage.guidanceTimer == nil, "close retained owner state")
check(newPage.addressPrompts == 1, "close lost address prompt")
print("PASS: pagination rebuild, late cleanup, manual close and menu unblock")

XWHUDManager.showGifImagesHUD(in: XWHUDManager.window, gifFileName: "", message: "",
                             timer: 10, margin: 0)
let unrelated = XWHUDManager.currentHUD()!
let connectedPage = page(parent)
let connectedHUD = connectedPage.connectLoadingHUD!
check(connectedHUD !== unrelated, "guidance took ownership of window HUD")
connectedPage.deliverConnected()
check(connectedHUD.finished && connectedPage.guidanceTimer == nil, "connection did not end owned HUD")
check(!unrelated.finished && unrelated.closeAction == nil, "connection modified unrelated HUD")
unrelated.hide(animated: false)
check(!XWHUDManager.isVisible(), "connection left menu blocked")
print("PASS: host-specific ownership and connection success preserve unrelated HUD")

let timeoutPage = page(parent)
timeoutPage.space.applyDeviceAddressCount = 1
let timeoutHUD = timeoutPage.connectLoadingHUD!
timeoutPage.guidanceTimeout()
check(timeoutHUD.finished && timeoutPage.guidanceTimer == nil, "timeout did not finish guidance")
check(timeoutPage.addressPrompts == 1 && !XWHUDManager.isVisible(), "timeout prompt/menu state incorrect")
let disappearingPage = page(parent)
disappearingPage.space.applyDeviceAddressCount = 1
disappearingPage.viewDidDisappear(false)
check(!XWHUDManager.isVisible(), "disappearing page retained HUD")
print("PASS: timeout and page disappearance")

// Foundation timers and delayed selectors are real; canceled owners must not prompt at 10s.
RunLoop.current.run(until: Date().addingTimeInterval(10.1))
check(oldPage.addressPrompts == 0 && disappearingPage.addressPrompts == 0,
      "removed page fired a stale timeout prompt")
check(newPage.addressPrompts == 1 && timeoutPage.addressPrompts == 1,
      "finished page repeated its timeout prompt")
print("PASS: delayed timeout cancellation after removal, manual close and timeout")
