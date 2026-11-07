import Foundation
import CoreGraphics

// Boundaries only: production methods are inserted by the check script.
class UIViewController {
    var navigationController: Navigation?
    var isMovingFromParent = false
    var isBeingDismissed = false
    func viewWillAppear(_ animated: Bool) {}
    func viewDidAppear(_ animated: Bool) {}
    func viewWillDisappear(_ animated: Bool) {}
    func viewDidDisappear(_ animated: Bool) {}
}
final class Navigation {
    var viewControllers: [UIViewController] = []
    var isBeingDismissed = false
}
class UIView {
    static func performWithoutAnimation(_ body: () -> Void) { body() }
}
struct UIImage { let named: String }
final class Label { var text: String?; var isHidden = false }
final class ImageView { var image: UIImage?; var isHidden = false }
final class DeviceLightInfoSectionView: UIView {
    let titleLabel = Label(), contentLabel = Label()
    let showImageView = ImageView()
    var sectionViewClickCallback: (() -> Void)?
}
final class UITableView {
    var firstShowFlashScrollIndicators = false
    var contentOffset = CGPoint(x: 0, y: -64)
    var adjustedContentInset = (top: CGFloat(64), bottom: CGFloat(0))
    var contentSize = CGSize.zero
    var bounds = CGRect(x: 0, y: 0, width: 704, height: 400)
    var onReload: (() -> [Int])?
    var reloads: [[Int]] = []
    func reloadData() {
        let counts = onReload!()
        reloads.append(counts)
        contentSize.height = CGFloat(counts.reduce(0, +) * 44)
    }
    func layoutIfNeeded() {}
    func setContentOffset(_ value: CGPoint, animated: Bool) { contentOffset = value }
    func flashScrollIndicatorsIfNeeded() {}
    func dequeueReusableHeaderFooterView(withIdentifier: String) -> UIView? { DeviceLightInfoSectionView() }
}
final class Alert {
    var dismissals = 0
    func dismiss(animation: Bool) { dismissals += 1 }
}
final class Scene {
    let number: Int
    var name: String
    init(_ number: Int, _ name: String) { self.number = number; self.name = name }
}
struct SceneData { let sceneNumber: Int; let lightness: Int; let cct: Int }
final class Group { var name = "Group A" }
final class Node {
    var rssi: Int? = -90
    var scenes: [Scene] = [Scene(1, "Morning"), Scene(2, "Evening")]
    var sceneExecuteDatas = [SceneData(sceneNumber: 1, lightness: 0, cct: 0)]
    var group: Group? = Group()
    var singleDeviceDisplaySupportCct = true
    var firmwareUpdateServerModel: Int? = 1
    var firmwareVersion: String? = "1.0"
    static func getLightness100(lightness: Int) -> Int { lightness }
    func getEffectiveTemperature100(temperature: UInt16) -> Int { Int(temperature) }
}
struct Sample { let node: Node; let rssi: NSNumber }
struct Scan {
    let sample: (Sample) -> Void
    let finished: ([Sample]) -> Void
}
final class MeshLibManager {
    static let manager = MeshLibManager()
    var active: Scan?
    var scans: [Scan] = []
    var stops = 0
    func refreshNodesRSSI(withWaitFor: Int, nodeScan: @escaping (Sample) -> Void,
                          finished: @escaping ([Sample]) -> Void) {
        // Match SDK's reentrancy boundary: replacement completes the old scan
        // synchronously before installing the new callbacks.
        let previous = active
        active = nil
        previous?.finished([])
        let next = Scan(sample: nodeScan, finished: finished)
        scans.append(next)
        active = next
    }
    func stopRefreshNodesRSSI() {
        stops += 1
        let previous = active
        active = nil
        previous?.finished([])
    }
    func reset() { active = nil; scans = []; stops = 0 }
}
struct FirmwareUpdateInformationGet { let firstIndex: Int; let entriesLimit: Int }
enum MeshAPI {
    static var completions: [(Int?) -> Void] = []
    static func sendMessage(message: FirmwareUpdateInformationGet, model: Int,
                            result: @escaping (Int?) -> Void) { completions.append(result) }
}
final class Coordinator {
    enum Phase { case idle, reading }
    var phase = Phase.idle
    var reads = 0, finishes = 0
    @discardableResult func read() -> Bool { reads += 1; return true }
    func finishPage() { finishes += 1 }
    func detach() { finishes += 1 }
}
struct TTLContext { var isVisible = true }
extension String { var localizedString: String { self } }
let spaceDataChangedNotificaitonName = "InformationFixtureFirmwareChanged"
enum SpaceChangeDataType { case device }

final class Information: UIViewController {
    typealias SectionType = DeviceInformationSection
    let pageSession = DeviceInformationPageSession()
    let node = Node()
    var tableView: UITableView! = UITableView()
    var sections: [SectionType] = [.deviceInfo, .group, .scene]
    var expandedSections: Set<SectionType> = [.deviceInfo, .scene]
    var snapshot = DeviceInformationSnapshot<Int>(sections: [], expandedSections: [],
        deviceRows: [], groupText: "", sceneRows: [], sceneTextOverride: nil)
    var sceneTextOverride: String?
    var groupTextOverride: String?
    let emptyGroupText = "No group"
    var ttlInitialReadPending = true
    var informationRequestsStarted = false
    var informationTimeReading = false
    var informationFirmwareReading = false
    var ttlContext: TTLContext? = TTLContext()
    var ttlCoordinator: Coordinator? = Coordinator()
    var gatewayTimeCoordinator: Coordinator? = Coordinator()
    var lightTimeCoordinator: Coordinator? = Coordinator()
    var ttlAlert: Alert?
    var ttlProgressAlert: Alert?
    func makeDeviceInfoRows() -> [Int] { Array(0..<12) }
    func updateTTLPresentation() { reloadInformation() }
    // PRODUCTION
}

func require(_ value: @autoclosure () -> Bool, _ message: String) {
    precondition(value(), message)
}
func page() -> Information {
    MeshLibManager.manager.reset()
    MeshAPI.completions = []
    let result = Information()
    let navigation = Navigation()
    navigation.viewControllers = [result]
    result.navigationController = navigation
    result.tableView.onReload = { [weak result] in
        guard let result else { return [] }
        return (0..<result.numberOfSections(in: result.tableView)).map {
            result.tableView(result.tableView, numberOfRowsInSection: $0)
        }
    }
    result.viewWillAppear(false)
    result.viewDidAppear(false)
    return result
}

func snapshotsAndEmptyScenes() {
    let p = page()
    require(p.tableView.reloads.last == [12, 0, 2], "Bugly initial shape")
    let oldScene = p.node.scenes[0]
    oldScene.name = "Changed elsewhere"
    p.node.scenes = []
    p.node.group?.name = "Changed group"
    require(p.tableView(p.tableView, numberOfRowsInSection: 2) == 2,
            "External scene mutation cannot change count before presentation commits")
    require(p.snapshot.sceneRows[0].name == "Morning" && p.snapshot.groupText == "Group A",
            "Snapshot must copy values, not retain mutable scene/group presentation")
    let oldHeader = p.tableView(p.tableView, viewForHeaderInSection: 2) as! DeviceLightInfoSectionView
    require(!oldHeader.showImageView.isHidden && oldHeader.contentLabel.isHidden,
            "Header follows the same still-published scene snapshot as row count")
    MeshLibManager.manager.active!.sample(Sample(node: p.node, rssi: -40))
    require(p.tableView.reloads.last == [12, 0, 0], "RSSI commits all sections, including 2 -> 0")
    let emptyHeader = p.tableView(p.tableView, viewForHeaderInSection: 2) as! DeviceLightInfoSectionView
    require(emptyHeader.contentLabel.text == "device_not_added_scene" && emptyHeader.showImageView.isHidden,
            "Empty scene state updates header and rows together")
    require(p.node.rssi == -40 && MeshLibManager.manager.stops == 1,
            "Synchronous stop completion cannot replace the accepted RSSI with nil")

    p.node.scenes = [Scene(3, "Third"), Scene(4, "Fourth")]
    p.node.sceneExecuteDatas = [SceneData(sceneNumber: 3, lightness: 50, cct: 25)]
    MeshAPI.completions[0](1)
    require(p.tableView.reloads.last == [12, 0, 2], "Firmware refresh also handles 0 -> 2")
    require(p.snapshot.sceneRows[0].content == "brightness-50%.cct-25%" && p.snapshot.sceneRows[1].content == nil,
            "Scene values include CCT and clear content for missing execution data")
    p.node.scenes = [Scene(5, "Fifth"), Scene(6, "Sixth")]
    p.reloadInformation()
    require(p.snapshot.sceneRows.map(\.name) == ["Fifth", "Sixth"], "Equal counts still replace row content")
    require(p.snapshot.section(at: -1) == nil && p.snapshot.rowCount(in: 7) == 0, "Stale section is safe")
}

func expansionOverridesAndScroll() {
    let p = page()
    p.tableView.contentOffset.y = 100
    p.reloadInformation()
    require(p.tableView.contentOffset.y == 100, "Refresh preserves a valid scroll offset")
    let sceneHeader = p.tableView(p.tableView, viewForHeaderInSection: 2) as! DeviceLightInfoSectionView
    sceneHeader.sectionViewClickCallback!()
    p.node.scenes = []
    p.reloadInformation()
    require(p.tableView.reloads.last == [12, 0, 0], "Collapsed scene tolerates external removal")
    p.node.scenes = [Scene(3, "New")]
    MeshAPI.completions[0](nil)
    require(p.tableView.reloads.last == [12, 0, 0], "Firmware timeout keeps scene collapsed")
    sceneHeader.sectionViewClickCallback!()
    require(p.tableView.reloads.last == [12, 0, 1], "Expanding uses current scene snapshot")
    let deviceHeader = p.tableView(p.tableView, viewForHeaderInSection: 0) as! DeviceLightInfoSectionView
    deviceHeader.sectionViewClickCallback!()
    require(p.tableView.contentOffset.y == -64, "Content shrink clamps scrolling to valid bounds")
    p.expandedSections.insert(.deviceInfo)
    p.sceneTextOverride = "Linked to scene"
    p.groupTextOverride = "Linked to group"
    p.reloadInformation()
    require(p.tableView.reloads.last == [12, 0, 0] && p.snapshot.sceneTextOverride == "Linked to scene"
            && p.snapshot.groupText == "Linked to group", "Switch override has header text and no scene rows")
    let overrideHeader = p.tableView(p.tableView, viewForHeaderInSection: 2) as! DeviceLightInfoSectionView
    require(overrideHeader.contentLabel.text == "Linked to scene", "Override is used by the production header")
    p.sections = [.deviceInfo]
    p.reloadInformation()
    require(p.tableView.reloads.last == [12] && p.snapshot.sceneRows.isEmpty, "Gateway hides both optional sections")
    p.sections = [.deviceInfo, .group]
    p.reloadInformation()
    require(p.tableView.reloads.last == [12, 0], "EFC/EL hides scene only")
}

func exitAndSharedScanner() {
    let p = page()
    let old = MeshLibManager.manager.active!
    let alert = Alert()
    p.ttlProgressAlert = alert
    p.viewWillDisappear(true)
    require(alert.dismissals == 1 && p.ttlProgressAlert == nil, "Leaving dismisses the page's progress")
    let reloadCount = p.tableView.reloads.count
    // A new owner replaces the scan, synchronously completing Information's scan.
    var newSamples = 0
    MeshLibManager.manager.refreshNodesRSSI(withWaitFor: 10, nodeScan: { _ in newSamples += 1 }, finished: { _ in })
    old.sample(Sample(node: p.node, rssi: -10))
    old.finished([])
    MeshAPI.completions[0](nil)
    require(!p.informationFirmwareReading && p.ttlCoordinator!.reads == 0,
            "Hidden firmware completion clears bookkeeping without starting TTL")
    require(p.tableView.reloads.count == reloadCount && p.node.rssi == -90
            && MeshLibManager.manager.stops == 0, "Old page neither renders nor stops a newer scan")
    MeshLibManager.manager.active!.sample(Sample(node: p.node, rssi: -30))
    require(newSamples == 1, "Lights scanner still owns callbacks")
    p.navigationController = nil // UIKit may clear the navigation parent before didDisappear.
    p.viewDidDisappear(true)
    require(p.pageSession.isFinished && p.ttlCoordinator!.finishes == 1
            && p.lightTimeCoordinator!.finishes == 1, "A removed page detaches coordinators")
    p.viewWillAppear(false)
    p.viewDidAppear(false)
    require(p.tableView.reloads.count == reloadCount, "Finished page cannot be revived by delayed lifecycle calls")
}

func cancelledTransitionAndLateReplies() {
    let p = page()
    let old = MeshLibManager.manager.active!
    let oldHeader = p.tableView(p.tableView, viewForHeaderInSection: 2) as! DeviceLightInfoSectionView
    p.viewWillDisappear(true)
    // Cancel interactive pop: the controller remains in its navigation stack.
    p.viewWillAppear(true)
    p.viewDidAppear(true)
    let count = p.tableView.reloads.count
    old.sample(Sample(node: p.node, rssi: -10))
    old.finished([])
    oldHeader.sectionViewClickCallback!()
    require(p.tableView.reloads.count == count && MeshLibManager.manager.stops == 0,
            "Reappearance never revives old scan or header callbacks")
    require(MeshAPI.completions.count == 1 && p.lightTimeCoordinator!.reads == 1
            && p.ttlCoordinator!.finishes == 0, "Cancelled pop preserves pending work without duplicate reads/detach")
    MeshAPI.completions[0](1)
    require(p.ttlCoordinator!.reads == 1 && !p.informationFirmwareReading, "Resumed page can advance to initial TTL")
    let afterFirmware = p.tableView.reloads.count
    MeshAPI.completions[0](nil)
    require(p.tableView.reloads.count == afterFirmware, "Duplicate firmware completion is ignored")
    let replacement = Node()
    MeshLibManager.manager.active!.sample(Sample(node: replacement, rssi: -5))
    require(p.node.rssi == -90 && MeshLibManager.manager.stops == 0, "A different Node instance cannot satisfy the page scan")
    MeshLibManager.manager.active!.finished([])
    require(p.node.rssi == nil, "Current scan timeout clears RSSI normally")
}

func hiddenCompletionThenResumeAndFreshPage() {
    let p = page()
    p.viewWillDisappear(true)
    p.viewDidDisappear(true) // still in stack: temporary cover, not a final exit
    require(!p.pageSession.isFinished, "Temporary disappearance must not finish the page")
    MeshAPI.completions[0](nil)
    require(p.ttlCoordinator!.reads == 0, "No follow-up reads while hidden")
    p.viewWillAppear(false)
    p.viewDidAppear(false)
    require(p.ttlCoordinator!.reads == 1 && MeshAPI.completions.count == 1,
            "Hidden completion does not leave the resumed page stuck or duplicate firmware")
    let oldScan = MeshLibManager.manager.active!
    let oldFirmware = MeshAPI.completions[0]
    p.viewWillDisappear(true)
    p.navigationController!.viewControllers = []
    p.viewDidDisappear(true)
    let fresh = page()
    let before = fresh.tableView.reloads.count
    oldScan.sample(Sample(node: p.node, rssi: -20))
    oldScan.finished([])
    oldFirmware(1)
    require(fresh.tableView.reloads.count == before && fresh.ttlCoordinator!.reads == 0
            && MeshLibManager.manager.stops == 0, "A previous controller cannot affect fresh Information")
}

snapshotsAndEmptyScenes()
expansionOverridesAndScroll()
exitAndSharedScanner()
cancelledTransitionAndLateReplies()
hiddenCompletionThenResumeAndFreshPage()
print("PASS: Information snapshot, production refresh/lifecycle callbacks, shared scan ownership and resume (5 groups)")
