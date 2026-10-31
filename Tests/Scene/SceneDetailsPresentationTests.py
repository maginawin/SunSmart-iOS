"""Run production detail routing/update/status methods with UIKit value sinks.

Exercises saved-intent transitions and view reuse; this is not layout/device QA.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
page = (root / 'SunSmart/Main/Scene/Controller/SceneViewController.swift').read_text()
view = (root / 'SunSmart/Main/Scene/View/SceneDevicesSelectionView.swift').read_text()

def function(source, marker):
    start = source.index(marker)
    opening = source.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end].replace('private func', 'func')

layout = page[page.index('enum SceneDetailLayout'):page.index('class SceneViewController')]
swift = r'''
import Foundation
import CoreGraphics
extension String { var localizedString: String { self == "scene_cleanup_count" ? "%d devices pending cleanup" : self } }
enum SceneKind { case groups, devices }
struct Operation: Equatable { enum Action { case write, remove }; var action: Action }
struct SceneConfiguration: Equatable {
    var kind: SceneKind = .devices
    var deviceMembers = [1]
    var pendingOperations: [Operation] = []
    var isDeleting = false
}
struct SceneGroupSyncSnapshot {
    var isCurrent = true
    var pendingCleanup: Set<Int> = []
    var needsAnySync = false
}
struct SceneDraft {
    var configuration: SceneConfiguration
    init(scene: Scene) throws {
        if scene.rejectDraft { throw NSError(domain: "fixture", code: 1) }
        configuration = scene.info.configuration!
    }
}
final class SceneDraftSelection { let draft: SceneDraft; init(draft: SceneDraft) { self.draft = draft } }
final class Group {}
final class Info { var configuration: SceneConfiguration? = .init(); var configurationLoadFailed = false; var groups: [Group] = [] }
final class Scene { let info = Info(); var name = "Scene A"; var rejectDraft = false }
final class Constraints {
    var top: Constraints { self }; var left: Constraints { self }; var right: Constraints { self }; var bottom: Constraints { self }
    @discardableResult func equalTo(_ value: Any) -> Constraints { self }
    func offset(_ value: Int) {}
    func makeConstraints(_ body: (Constraints) -> Void) { body(self) }
    func updateConstraints(_ body: (Constraints) -> Void) { body(self) }
}
enum Color { case clear, brand }
let Bar_Color = Color.brand
func FONTS(_ value: Int) -> Int { value }
func SCRYFrom(_ value: Int) -> Int { value }
class View {
    var isHidden = false
    var frame = CGRect.zero
    var bounds = CGRect.zero
    let snp = Constraints()
    var safeAreaLayoutGuide: Int { 0 }
    var removed = false
    func addSubview(_ view: View) {}
    func removeFromSuperview() { removed = true }
    func setNeedsLayout() {}
}
final class Label: View { var text: String?; var font = 0 }
final class EmptyView: View { let button = Button(), titleLabel = Label() }
final class Collection: View {
    enum Position { case center }
    var emptyText: String?
    var emptyView: EmptyView?
    var buttonText: String?
    var buttonAction: (() -> Void)?
    var contentOffset = CGPoint.zero
    func reloadData() {}
    func showEmptyDataView(title: String, buttonText: String? = nil, position: Position, bottomMargin: Double, btnClickBack: (() -> Void)? = nil) {
        emptyText = title; emptyView = EmptyView(); self.buttonText = buttonText; buttonAction = buttonText == nil ? nil : btnClickBack
    }
    func hideEmptyDataView() { emptyText = nil; emptyView = nil; buttonText = nil; buttonAction = nil }
    func setContentOffset(_ point: CGPoint, animated: Bool) { contentOffset = point; bounds.origin = point }
}
final class PageControl: View { var numberOfPages = 0 }
final class Button: View {
    enum State { case normal }
    var isEnabled = true, backgroundColor = Color.clear
    var titleLabel: Label? = Label()
    func setTitleColor(_ color: Color, for state: State) {}
}
final class Navigation { var title: String?; var rightBarButtonItem: Button? = Button() }
struct Space { enum Operation { case edit }; var sceneOperates: Set<Operation> = [.edit] }
struct SpacePageRevision {}
enum NodeSyncStatusRefresh { static func sceneGroupAppearances(_ groups: [Group]) -> [Int] { [] } }
final class SyncDisplay { var currentSnapshot: SceneGroupSyncSnapshot? }
// LAYOUT
final class SceneDevicesSelectionView: View {
    var selection: SceneDraftSelection
    let displayingSavedConfiguration: Bool
    var syncSnapshot: SceneGroupSyncSnapshot?
    var scrollOffset = 0
    init(selection: SceneDraftSelection, displayingSavedConfiguration: Bool) {
        self.selection = selection; self.displayingSavedConfiguration = displayingSavedConfiguration
    }
    // UPDATE_SAVED
    // SAVED_STATUS
}
final class Page {
    let scene = Scene(), titleLabel = Label(), collectionView = Collection(), pageControl = PageControl()
    let view = View(), navigationItem = Navigation(), detailStatusLabel = Label(), syncDisplay = SyncDisplay()
    var space = Space(), detailLayout: SceneDetailLayout = .groups
    var groups: [Group] = [], devicesView: SceneDevicesSelectionView?, appearances: [Int] = []
    var refreshData = true, renderedRevision: SpacePageRevision?
    let columnNum = 3, rowNum = 3
    var deviceMode: Bool { detailLayout == .devices }
    func refreshSyncStatus() {}
    var settingsOpened = 0
    func settings() { settingsOpened += 1 }
    // UPDATE_UI
    // UPDATE_STATUS
    // EMPTY_UI
}
var checks = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) { precondition(value(), message); checks += 1 }
let page = Page()
page.updateUI()
check(page.deviceMode && !page.devicesView!.isHidden && page.collectionView.isHidden, "nonempty device layout")
check(page.collectionView.emptyView == nil, "device members must not create an empty placeholder")
check(page.titleLabel.isHidden && page.navigationItem.title == "Scene A", "device navigation title")
let details = page.devicesView!
details.scrollOffset = 240
page.scene.name = "Renamed"
page.updateUI()
check(page.devicesView === details && details.scrollOffset == 240 && page.navigationItem.title == "Renamed", "reuse on notification and rename")
page.scene.info.configuration!.deviceMembers = []
page.scene.info.configuration!.pendingOperations = [.init(action: .remove)]
let saved = page.scene.info.configuration
page.updateUI()
check(page.detailLayout == .emptyDevices && page.devicesView == nil && details.removed, "last member removal switches view")
check(!page.collectionView.isHidden && !page.titleLabel.isHidden && page.navigationItem.title == nil, "default title and grid restored")
check(page.collectionView.emptyText == "scene_no_members" && page.pageControl.numberOfPages == 0, "default empty text and paging")
check(page.collectionView.buttonText == "settings", "editable empty device scene offers Settings")
page.collectionView.buttonAction?()
check(page.settingsOpened == 1, "empty Settings button uses existing settings entry")
page.scene.info.configuration!.isDeleting = true
page.updateUI()
check(page.collectionView.buttonText == nil, "deleting scene must not offer Settings")
page.scene.info.configuration!.isDeleting = false
page.updateUI()
check(page.detailStatusLabel.text == "1 devices pending cleanup" && !page.detailStatusLabel.isHidden, "empty cleanup remains visible")
check(page.scene.info.configuration == saved, "presentation must not mutate kind or cleanup")
page.syncDisplay.currentSnapshot = .init()
page.updateDetailStatus()
check(page.detailStatusLabel.isHidden, "completed cleanup clears stale status")
page.syncDisplay.currentSnapshot = nil
page.scene.info.configuration!.pendingOperations = []
page.updateUI()
check(page.detailStatusLabel.isHidden && page.detailLayout == .emptyDevices, "permanent deletion/clean empty configuration")
page.scene.info.configuration!.deviceMembers = [1, 2]
page.updateUI()
check(page.deviceMode && page.devicesView !== details && page.devicesView!.selection.draft.configuration.deviceMembers.count == 2, "re-add restores cards")
page.space.sceneOperates = []
page.updateUI()
check(page.navigationItem.rightBarButtonItem?.isEnabled == false, "viewer cannot edit")
page.scene.rejectDraft = true
page.updateUI()
check(page.detailLayout == .unavailable && page.collectionView.emptyText == "scene_details_unavailable" && page.devicesView == nil, "failed draft is not an empty scene")
check(page.collectionView.buttonText == nil, "unavailable details must not offer Settings")
page.scene.rejectDraft = false
page.scene.info.configurationLoadFailed = true
page.scene.info.configuration = nil
page.updateUI()
check(page.detailLayout == .unavailable, "corrupt configuration is not legacy empty")
page.scene.info.configurationLoadFailed = false
page.scene.info.groups = [Group()]
page.updateUI()
check(page.detailLayout == .groups && page.groups.count == 1 && page.collectionView.emptyText == nil, "legacy Groups retained")
page.scene.info.groups = []
page.collectionView.bounds = CGRect(x: 320, y: 0, width: 320, height: 392)
page.collectionView.contentOffset = CGPoint(x: 320, y: 0)
page.updateUI()
check(page.collectionView.emptyText == "scene_no_members", "legacy empty remains valid")
check(page.collectionView.buttonText == nil, "viewer empty scene must not offer Settings")
page.space.sceneOperates = [.edit]
page.updateUI()
check(page.collectionView.buttonText == "settings", "editable empty group scene offers Settings")
check(page.collectionView.contentOffset == .zero && page.collectionView.emptyView?.frame == CGRect(x: 0, y: 0, width: 320, height: 392), "empty groups reset pagination and fill current bounds")
let status = SceneDevicesSelectionView.savedStatus
check(status(nil, nil) == nil, "unknown read must not claim pending work")
check(status(.init(pendingOperations: [.init(action: .write)]), nil) == "scene_pending_sync", "durable pending write")
check(status(.init(), .init(isCurrent: false, pendingCleanup: [1], needsAnySync: true)) == nil, "stale snapshot ignored")
check(status(.init(pendingOperations: [.init(action: .remove)]), .init(isCurrent: false)) == "1 devices pending cleanup", "fallback to durable cleanup")
check(status(.init(), .init(needsAnySync: true)) == "scene_pending_sync", "confirmed async pending work")
check(SceneDetailLayout.resolve(configuration: .init(), loadFailed: false, draftAvailable: true) == .devices, "routing independent of online/resolved node count")
print("Scene details presentation: \(checks) checks passed")
'''
for marker, replacement in {
    '// LAYOUT': layout,
    '// UPDATE_UI': function(page, '    private func updateUI()'),
    '// UPDATE_STATUS': function(page, '    private func updateDetailStatus()'),
    '// EMPTY_UI': function(page, '    private func updateEmptyUI()'),
    '// UPDATE_SAVED': function(view, '    func updateSavedConfiguration('),
    '// SAVED_STATUS': function(view, '    static func savedStatus('),
}.items():
    swift = swift.replace(marker, replacement)
with tempfile.TemporaryDirectory(prefix='scene-details-presentation-') as directory:
    path = Path(directory)
    (path / 'main.swift').write_text(swift)
    subprocess.run(['swiftc', str(path / 'main.swift'), '-o', str(path / 'tests')], check=True)
    subprocess.run([str(path / 'tests')], check=True)
