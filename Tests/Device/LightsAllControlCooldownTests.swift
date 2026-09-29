// Executes production tap, command, cooldown, lifecycle and Cell rendering code.
// UIKit/Mesh doubles cannot verify actual animation appearance or BLE delivery.
import Foundation
import CoreGraphics
import Darwin

struct UIColor: Equatable {
    let value: String
    static let white = UIColor(value: "white")
}
let Bar_Color = UIColor(value: "brand")
let Title_Color = UIColor(value: "title")
func RGB(_ r: Int, _ g: Int, _ b: Int) -> UIColor { UIColor(value: "\(r),\(g),\(b)") }
func SCRYFrom(_ value: Int) -> Int { value }
var isIPad = false
var routeTest = false
extension String { var localizedString: String { self } }
extension IndexPath {
    init(item: Int, section: Int) { self.init(indexes: [section, item]) }
    var item: Int { self[1] }
}
enum DeviceAllOnOffState { case on, off, disable }
class View {
    var superview: View?
    var bounds = CGRect.zero
    func addSubview(_ view: View) { view.superview = self }
}
class UIViewController {
    var view = View()
    var wm_pageController: UIViewController?
    var navigationController: NavigationController?
    func viewDidAppear(_ animated: Bool) {}
    func viewWillDisappear(_ animated: Bool) {}
}
final class NavigationController { var interactivePopGestureRecognizer: Gesture? }
final class Gesture { var isEnabled = true }
final class UIApplication {
    enum State { case active, background }
    static let shared = UIApplication()
    var applicationState = State.active
}
class UICollectionViewCell {
    var backgroundColor: UIColor?
    init(frame: CGRect) {}
    required init?(coder: NSCoder) { fatalError() }
    func prepareForReuse() {}
}
class DevicesViewCell: UICollectionViewCell {
    let iconImageView = ImageView()
    let progressView = ProgressView()
    let nameLabel = Label()
}
final class ProgressView { var isHidden = false }
final class Label { var text: String?; var textColor: UIColor? }
struct UIImage {
    let name: String
    init?(named: String) { name = named }
    func withTintColor(_ color: UIColor) -> UIImage { self }
}
final class ImageView {
    enum ContentMode { case scaleToFill, scaleAspectFit }
    var contentMode = ContentMode.scaleToFill
    var image: UIImage?
    let layer = Layer()
    let snp = Constraints()
}
final class Layer {
    var animations = Set<String>()
    var starts = 0
    var lastDuration: TimeInterval?
    func animation(forKey key: String) -> Bool? { animations.contains(key) ? true : nil }
    func removeAnimation(forKey key: String) { animations.remove(key) }
    func addRotationAnimation(duration: TimeInterval, repeatCount: Int, animationKey: String) {
        lastDuration = duration
        starts += 1; animations.insert(animationKey)
    }
}
final class Constraints {
    var top: Constraints { self }
    func equalTo(_ value: Int) {}
    func updateConstraints(_ block: (Constraints) -> Void) { block(self) }
}
final class UICollectionView {
    var firstShowFlashScrollIndicators = false
    var visibleCells: [UICollectionViewCell] = []
    var onReload: (() -> Void)?
    func cellForItem(at indexPath: IndexPath) -> UICollectionViewCell? { visibleCells.first }
    func reloadData() { onReload?() }
    func flashScrollIndicatorsIfNeeded() {}
}
final class Node {
    var state = true
    var isOn = false
    var lightness: UInt16 = 100
    var trunOffLightness: UInt16?
    var isEmergencySignController = false
    var isKeybindComplete = true
    var effectiveSupportCct = false
    var primaryUnicastAddress: UInt16 = 1
}
final class DeviceLightControlView: View {
    enum Option { case level, cct }
    var supportOptions: [Option] = []
    var showCount = 0
    func show() { showCount += 1 }
    func updateCctRange(_ range: ClosedRange<UInt16>) {}
}
final class DeviceNameFilterSession { func removeObserver(_ id: UUID) {} }
let spacePageDisableScrollNotificaitonName = "spacePageDisableScroll"
enum LightGroupControlCommandSender {
    static var sent: [Bool] = []
    static func setAllOnOff(isOn: Bool) { sent.append(isOn) }
}
final class MeshLibManager {
    static let manager = MeshLibManager()
    weak var messageDelegate: AnyObject?
    func register(_ owner: AnyObject) {}
}
enum MeshAPI { static func getNodeOnOffState(address: UInt16) {} }

// PRODUCTION_CONTROLLER_AND_CELL

final class TestClock {
    var now: TimeInterval = 100
    func advance(_ seconds: TimeInterval) { now += seconds }
}

final class WeakPage {
    weak var value: DeviceLightsViewController?
    init(_ value: DeviceLightsViewController?) { self.value = value }
}

@main
struct LightsAllControlCooldownTests {
    static let allIndex = IndexPath(item: 0, section: 0)

    static func page(count: Int, clock: TestClock) -> DeviceLightsViewController {
        let page = DeviceLightsViewController()
        page.allControlNow = { clock.now }
        page.devices = (0..<count).map { _ in Node() }
        page.showsAllControl = count > 0
        page.collectionView.visibleCells = [DeviceAllOnOffViewCell(frame: .zero)]
        page.collectionView.onReload = { [weak page] in
            guard let page, let cell = page.collectionView.visibleCells.first as? DeviceAllOnOffViewCell else { return }
            cell.prepareForReuse()
            page.configureAllControlCell(cell)
        }
        page.viewDidAppear(false)
        return page
    }

    static func cell(_ page: DeviceLightsViewController) -> DeviceAllOnOffViewCell {
        page.collectionView.visibleCells.first as! DeviceAllOnOffViewCell
    }

    static func tap(_ page: DeviceLightsViewController) {
        page.collectionView(page.collectionView, didSelectItemAt: allIndex)
    }

    static func main() {
        for (count, seconds) in [(1, 1), (100, 1), (101, 2), (200, 2), (201, 3), (1000, 3)] {
            let clock = TestClock()
            let page = page(count: count, clock: clock)
            LightGroupControlCommandSender.sent = []
            tap(page)
            precondition(LightGroupControlCommandSender.sent == [true])
            precondition(page.allControlCooldownDeadline == clock.now + Double(seconds))
            precondition(cell(page).isLoading && cell(page).state == .on)
            precondition(cell(page).iconImageView.layer.lastDuration == 1.2)
            clock.advance(Double(seconds) - 0.001)
            for _ in 0..<20 { tap(page) }
            page.deviceAllSetting()
            precondition(page.controlAllOn == true && LightGroupControlCommandSender.sent == [true])
            precondition(page.lightControlView.showCount == 0)
            let oldWork = page.allControlCooldownWorkItem!
            clock.now = page.allControlCooldownDeadline!
            // A delayed expiry callback must not be needed to accept the next tap.
            tap(page)
            precondition(LightGroupControlCommandSender.sent == [true, false])
            precondition(page.devices.allSatisfy { !$0.isOn && $0.trunOffLightness == 100 })
            precondition(oldWork.isCancelled)
            let nextDeadline = page.allControlCooldownDeadline
            oldWork.perform()
            page.refreshAllControlCooldown() // A late wakeup always reads the current deadline.
            precondition(page.allControlCooldownDeadline == nextDeadline && cell(page).isLoading)
            clock.advance(Double(seconds))
            page.allControlCooldownWorkItem?.perform()
            precondition(!cell(page).isLoading && cell(page).state == .off)
            precondition(cell(page).iconImageView.layer.animations.isEmpty)
            page.deviceAllSetting()
            precondition(page.lightControlView.showCount == 1)
        }

        let clock = TestClock()
        let empty = page(count: 0, clock: clock)
        empty.toggleAllLights()
        precondition(empty.allControlCooldownDeadline == nil && empty.controlAllOn == nil)
        let page = page(count: 201, clock: clock)
        page.emergencyBlocked = true
        LightGroupControlCommandSender.sent = []
        tap(page)
        precondition(page.allControlCooldownDeadline == nil && page.controlAllOn == nil)
        precondition(LightGroupControlCommandSender.sent.isEmpty)
        page.emergencyBlocked = false
        // Offline / repair lights still contribute to the full Lights count.
        page.devices.forEach { $0.state = false; $0.isKeybindComplete = false }
        tap(page)
        precondition(page.allControlCooldownDeadline == clock.now + 3)
        precondition(LightGroupControlCommandSender.sent == [true] && cell(page).isLoading)
        precondition(cell(page).state == .disable)
        let deadline = page.allControlCooldownDeadline
        let originalCell = cell(page)
        let animationStarts = originalCell.iconImageView.layer.starts
        page.updateAllOnOffItemUI()
        precondition(originalCell.iconImageView.layer.starts == animationStarts, "Status refresh must not restart rotation")
        precondition(originalCell.iconImageView.image?.name == "site_entry_sync_loading")
        precondition(originalCell.iconImageView.contentMode == .scaleAspectFit)

        // Hiding All through filtering or scrolling does not shorten the deadline.
        page.showsAllControl = false
        page.collectionView(page.collectionView, didEndDisplaying: originalCell, forItemAt: allIndex)
        page.collectionView.visibleCells = []
        page.devices.removeLast(200)
        clock.advance(1)
        page.updateAllOnOffItemUI()
        let reused = DeviceAllOnOffViewCell(frame: .zero)
        page.collectionView.visibleCells = [reused]
        page.showsAllControl = true
        page.collectionView(page.collectionView, willDisplay: reused, forItemAt: allIndex)
        precondition(reused.isLoading && page.allControlCooldownDeadline == deadline)
        reused.prepareForReuse()
        precondition(!reused.isLoading && reused.iconImageView.layer.animations.isEmpty)
        page.configureAllControlCell(reused)
        precondition(reused.isLoading)

        let pending = page.allControlCooldownWorkItem!
        page.viewWillDisappear(false)
        precondition(pending.isCancelled && page.allControlCooldownWorkItem == nil && !reused.isLoading)
        clock.advance(0.5)
        page.viewDidAppear(false)
        precondition(reused.isLoading && page.allControlCooldownDeadline == deadline)
        UIApplication.shared.applicationState = .background
        page.suspendAllControlCooldownDisplay()
        clock.advance(30)
        UIApplication.shared.applicationState = .active
        page.refreshAllControlCooldown()
        precondition(!reused.isLoading && page.allControlCooldownWorkItem == nil)
        precondition(LightGroupControlCommandSender.sent == [true], "Expiry must never resend")
        tap(page)
        precondition(page.allControlCooldownDeadline == clock.now + 1, "Next tap recounts lights")

        // Expiry redraws the latest state, rather than restoring the old target.
        page.controlAllOn = true
        page.devices[0].state = true
        clock.advance(1)
        page.refreshAllControlCooldown()
        precondition(!reused.isLoading && reused.state == .on)
        isIPad = true
        tap(page)
        precondition(reused.iconImageView.image?.name == "site_entry_sync_loading")
        precondition(reused.iconImageView.contentMode == .scaleAspectFit)
        precondition(reused.iconImageView.layer.lastDuration == 1.2)
        isIPad = false

        let initiallyOn = Self.page(count: 2, clock: clock)
        initiallyOn.devices[0].isOn = true
        initiallyOn.updateAllOnOffItemUI()
        routeTest = true
        tap(initiallyOn)
        precondition(initiallyOn.controlAllOn == false && LightGroupControlCommandSender.sent.last == false)
        precondition(initiallyOn.devices[0].isOn, "Route diagnostics must retain their existing local-state behavior")
        precondition(cell(initiallyOn).isLoading)
        routeTest = false

        var exiting: DeviceLightsViewController? = Self.page(count: 1, clock: clock)
        tap(exiting!)
        let exitingWork = exiting!.allControlCooldownWorkItem!
        let released = WeakPage(exiting)
        exiting = nil
        precondition(released.value == nil && exitingWork.isCancelled)
        let recreated = Self.page(count: 1, clock: clock)
        precondition(!recreated.isAllControlCoolingDown, "A recreated page starts without the old cooldown")
        print("PASS: All cooldown boundaries, repeated taps, long press, rejection, commands, cell reuse, hide/return/background, expiry and deallocation")
    }
}
