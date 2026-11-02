import Foundation

extension IndexPath { var item: Int { self[0] }; var row: Int { self[0] } }
final class ScenesViewCell {
    var isExecuting = false
    var animations = 0
    func showExecuteAnimation() { animations += 1 }
}
final class UICollectionView {
    let cell = ScenesViewCell()
    func reloadData() {}
    func cellForItem(at indexPath: IndexPath) -> AnyObject? { cell }
}
final class SpaceData {
    enum Operate { case control, edit }
    var sceneOperates: [Operate] = [.control]
}
final class MeshLibManager {
    static let manager = MeshLibManager()
    var isMeshNetworkConnected = true
}
enum MeshAPI {
    static var sent: [MeshMessageHandle] = []
    static func sendMessage(message: Any, model: Model) { sent.append(.init(message: message, model: model)) }
    static func sendMessage(message: Any, address: UInt16) { sent.append(.init(message: message, address: address)) }
}
final class ScenesControllerProbe {
    var scenes: [Scene] = []
    let space = SpaceData()
    var isEdit = false
    init(_ scenes: [Scene]) {
        MeshNetworkManager.instance.scenes = scenes
        self.scenes = visibleScenes
    }
    // PRODUCTION_VISIBLE_SCENES
    // PRODUCTION_LIST_RECALL
}
enum DeviceEmerFireData { static let reservedSceneNumbers: Set<UInt16> = [0xFFF0] }
final class UITableView { func reloadData() {} }
enum XWHUDManager { static func showTipHUD(_ text: String, isLineFeed: Bool) {} }
struct SpacePageRevision { var isCurrent: Bool { true } }
// PRODUCTION_SCENE_SNAPSHOT
final class SceneGroupDisplayState { var currentSnapshot: SceneGroupSyncSnapshot? }
struct ScheduleTargetSyncSnapshot { var scenes: Set<ObjectIdentifier> = [] }
final class ScheduleTargetDisplayState { var currentSnapshot: ScheduleTargetSyncSnapshot? }

struct UIScreen { static let main = UIScreen(); let bounds = CGRect() }
class PickerViewBoundary { init(frame: CGRect) {} }
final class ScheduleScenePickerProbe: PickerViewBoundary {
    typealias SceneSelectFinishedCallback = (Scene?) -> Void
    let scenes: [Scene]
    var selectScene: Scene?
    var schedule: Schedule?
    let syncDisplay = ScheduleTargetDisplayState()
    var sceneDisplays: [ObjectIdentifier: SceneGroupDisplayState] = [:]
    let collectionView = UICollectionView()
    let selectCallback: SceneSelectFinishedCallback?
    func setupUI() {}
    func observeSyncStatusChanges() {}
    convenience init(_ scenes: [Scene]) { self.init(scenes: scenes, selectScene: nil, selectBack: nil) }
    // PRODUCTION_SCHEDULE_INIT
    // PRODUCTION_SCHEDULE_PENDING
    // PRODUCTION_SCHEDULE_SELECT
}

struct SwitchSceneData {
    enum SceneType { case sceneA, sceneB, sceneC, sceneD }
    var type: SceneType = .sceneA
    var scene: Scene?
}
let Bar_Color = 1, SubText_Color = 2
func SCRXFrom(_ value: Double) -> Double { value }
func SCRYFrom(_ value: Double) -> Double { value }
class SwitchPageBoundary {
    enum Style { case line, center }
    var menuViewStyle = Style.line, menuViewLayoutMode = Style.center
    var progressHeight = 0.0, progressWidth = 0.0, progressViewBottomSpace = 0.0
    var titleSizeNormal = 0, titleSizeSelected = 0, progressColor = 0, titleColorNormal = 0, titleColorSelected = 0
    var menuItemWidth = 0.0, itemMargin = 0.0
    init(nibName: String?, bundle: Any?) {}
}
final class SwitchScenePageProbe: SwitchPageBoundary {
    enum TitleStyle { case lettered, numbered }
    let scenes: [Scene]
    let titleStyle: TitleStyle
    var sceneDatas: [SwitchSceneData]!
    // PRODUCTION_SWITCH_PAGE_INIT
}
final class SwitchScenePickerProbe {
    var editable = true
    let scenes: [Scene]
    var sceneData = SwitchSceneData()
    var sceneSelectCallback: ((SwitchSceneData?) -> Void)?
    init(_ scenes: [Scene]) { self.scenes = scenes }
    // PRODUCTION_SWITCH_SELECT
}

struct IdentifySelection {
    struct Draft { let scope: SceneScope }
    let draft: Draft
}
final class IdentifyDevicesProbe {
    let selection: IdentifySelection
    init(_ selection: IdentifySelection) { self.selection = selection }
    // PRODUCTION_IDENTITY_LOOKUP
}
extension Node {
    var isSupportVendorIdentify: Bool { false }
    var sunricherVendorModel: Model? { onoffModel }
}
struct SunricherVendorSet {
    enum Mode { case breathe(count: Int, period: Int) }
    enum Function { case identify(mode: Mode) }
    let function: Function
}
enum LightGroupControlCommandSender {
    static var identified: [UInt16] = []
    static func identify(address: UInt16) { identified.append(address) }
    static func sendVendorIdentify(_ message: SunricherVendorSet, model: Model) {}
}
final class IdentifyControllerProbe {
    var busy = false, active = true
    var selection: IdentifySelection?
    let devicesView: IdentifyDevicesProbe
    init(_ scope: SceneScope) {
        let value = IdentifySelection(draft: .init(scope: scope))
        selection = value; devicesView = IdentifyDevicesProbe(value)
    }
    func failed(_ error: Error) {}
    func tip(_ message: String) {}
    // PRODUCTION_IDENTIFY
}
