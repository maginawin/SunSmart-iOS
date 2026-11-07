"""Run production Scene cell binding with controlled asynchronous status reads."""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[2]
sys.dont_write_bytecode = True
sys.path.insert(0, str(root / 'scripts'))
from check_scene_configuration import function

source = (root / 'SunSmart/Main/Scene/View/ScenesViewCell.swift').read_text()
binding = source[source.index('    private var sceneRequestID'):source.index('    override init(')]
controller = (root / 'SunSmart/Main/Scene/Controller/ScenesViewController.swift').read_text()
swift = r'''
import Foundation
extension String { var localizedString: String { self } }
struct UIImage { let name: String; init(named: String) { name = named } }
final class ImageView { var image: UIImage? }
final class Label { var text: String? }
final class Animation { var animation = false }
class GroupsViewCell {
    let imageView = ImageView(), nameLabel = Label()
    func prepareForReuse() {}
}
final class Scene {
    struct Configuration { var isDeleting = false }
    struct Info { var imageId = 1; var configuration: Configuration? }
    var info = Info(), name = "scene"
    var number = 1, network: Network?, subNetworkId: String? = "subnet"
}
final class Network { let uuid = UUID() }
let sceneImageNames = ["scene1", "scene2"]
struct Snapshot { let needsAnySync: Bool }
enum NodeSyncStatusRefresh {
    static var callbacks: [(Snapshot?) -> Void] = []
    static func requestSceneGroups(scene: Scene, owner: AnyObject, completion: @escaping (Snapshot?) -> Void) { callbacks.append(completion) }
    static func request(scene: Scene, owner: AnyObject, completion: @escaping (Bool) -> Void) { callbacks.append { completion($0?.needsAnySync != false) } }
}
final class Cell: GroupsViewCell {
    let animationView = Animation()
// BINDING
}
let cell = Cell(), first = Scene(), second = Scene()
second.info.imageId = 2
func expect(_ image: String, _ message: String) {
    precondition(cell.imageView.image?.name == image, message)
}
cell.scene = first
expect("scene1", "initial pending read must not show a sync failure")
NodeSyncStatusRefresh.callbacks.last!(Snapshot(needsAnySync: false))
cell.scene = first
expect("scene1", "list reload must not flash a sync warning")
NodeSyncStatusRefresh.callbacks.last!(nil)
expect("scene1", "unavailable read is not a confirmed sync failure")
cell.scene = first
NodeSyncStatusRefresh.callbacks.last!(Snapshot(needsAnySync: true))
expect("sync_failed_big", "confirmed pending work must show warning")
cell.scene = first
expect("sync_failed_big", "retain known warning while checking same scene")
NodeSyncStatusRefresh.callbacks.last!(nil)
expect("sync_failed_big", "unavailable result must not erase a known warning")
cell.scene = first
NodeSyncStatusRefresh.callbacks.last!(Snapshot(needsAnySync: false))
expect("scene1", "successful synchronization clears warning")
let stale = NodeSyncStatusRefresh.callbacks.last!
cell.prepareForReuse()
cell.scene = second
stale(Snapshot(needsAnySync: true))
expect("scene2", "late callback must not change reused cell")
NodeSyncStatusRefresh.callbacks.last!(Snapshot(needsAnySync: true))
cell.prepareForReuse()
cell.scene = first
expect("scene1", "another scene must not inherit old warning")

// Only UIKit rendering is substituted. Deliver the real list observer to the
// production row-reload method and bind the requested rows to production cells.
let sceneDataUpdateNotificationName = "sceneChanged"
enum DeviceEmerFireData { static let reservedSceneNumbers: [Int] = [] }
enum CATransaction { static func begin() {}; static func setDisableActions(_ value: Bool) {}; static func commit() {} }
extension IndexPath { init(row: Int, section: Int) { self.init(indexes: [section, row]) } }
final class Collection {
    let numberOfSections = 1
    var cells: [Cell] = [], data: [Scene] = []
    func numberOfItems(inSection section: Int) -> Int { cells.count }
    func reloadItems(at paths: [IndexPath]) { for path in paths { cells[path[1]].scene = data[path[1]] } }
}
class Controller { func viewWillAppear(_ animated: Bool) {} }
final class List: Controller {
    struct Space { let meshUUID: String; var meshNetworkId = "subnet" }
    struct View { let window = NSObject() }
    struct Revision { var isCurrent = true }
    let space: Space, collectionView = Collection()
    var scenes: [Scene]
    let visibleScenes: [Scene]
    var isPageVisible = true, refreshData = false, renderedRevision: Revision? = Revision()
    var viewIfLoaded: View? = View()
    init(_ data: [Scene], network: Network) {
        space = Space(meshUUID: network.uuid.uuidString)
        scenes = data; visibleScenes = data; collectionView.data = data
        collectionView.cells = data.map { _ in Cell() }
        super.init()
        // OBSERVE
    }
    func updateUI() {
        refreshData = false; scenes = visibleScenes
        collectionView.reloadItems(at: scenes.indices.map { IndexPath(row: $0, section: 0) })
    }
    // RELOAD
    // APPEAR
}
let network = Network()
first.network = network; second.network = network; second.number = 2
let list = List([first, second], network: network)
let card = list.collectionView.cells[0], other = list.collectionView.cells[1]
func changed(_ scene: Scene) { NotificationCenter.default.post(name: .init(sceneDataUpdateNotificationName), object: scene) }
func deliver(_ pending: Bool) { NodeSyncStatusRefresh.callbacks.last!(Snapshot(needsAnySync: pending)) }
changed(second); deliver(true)
changed(first); deliver(true)
let pendingRead = NodeSyncStatusRefresh.callbacks.last!
let initialReads = NodeSyncStatusRefresh.callbacks.count
changed(first)
precondition(NodeSyncStatusRefresh.callbacks.count == initialReads + 1)
deliver(false); pendingRead(Snapshot(needsAnySync: true))
precondition(card.imageView.image?.name == "scene1" && other.imageView.image?.name == "sync_failed_big")

let foreign = Scene()
foreign.network = Network()
changed(foreign)
foreign.network = network; foreign.subNetworkId = "other"; changed(foreign)
precondition(NodeSyncStatusRefresh.callbacks.count == initialReads + 1, "same Scene number in another Space must not rebind this card")

changed(first); deliver(true)
let beforeReturn = NodeSyncStatusRefresh.callbacks.count
list.isPageVisible = false
changed(first)
precondition(list.refreshData && NodeSyncStatusRefresh.callbacks.count == beforeReturn)
list.viewWillAppear(true)
precondition(NodeSyncStatusRefresh.callbacks.count == beforeReturn + 2)
NodeSyncStatusRefresh.callbacks[beforeReturn](Snapshot(needsAnySync: false)); deliver(true)
precondition(card.imageView.image?.name == "scene1" && other.imageView.image?.name == "sync_failed_big")
print("PASS: Scene icons after single-item refresh, offscreen re-entry, scoped notifications, stale reads and reuse")
'''.replace('// BINDING', binding).replace('// OBSERVE', function(controller,
    '        NotificationCenter.default.addObserver(forName: .init(sceneDataUpdateNotificationName)')).replace(
    '// RELOAD', function(controller, '    private func reloadCollectionItem(')).replace(
    '// APPEAR', function(controller, '    override func viewWillAppear('))
with tempfile.TemporaryDirectory(prefix='scene-list-sync-') as directory:
    path = Path(directory)
    (path / 'main.swift').write_text(swift)
    subprocess.run(['swiftc', str(path / 'main.swift'), '-o', str(path / 'tests')], check=True)
    subprocess.run([str(path / 'tests')], check=True)
