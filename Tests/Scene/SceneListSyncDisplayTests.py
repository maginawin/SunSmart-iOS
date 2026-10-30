"""Run production Scene cell binding with controlled asynchronous status reads."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / 'SunSmart/Main/Scene/View/ScenesViewCell.swift').read_text()
binding = source[source.index('    private var sceneRequestID'):source.index('    override init(')]
swift = r'''
import Foundation
struct UIImage { let name: String; init(named: String) { name = named } }
final class ImageView { var image: UIImage? }
final class Label { var text: String? }
final class Animation { var animation = false }
class GroupsViewCell {
    let imageView = ImageView(), nameLabel = Label()
    func prepareForReuse() {}
}
final class Scene {
    struct Info { var imageId = 1 }
    var info = Info(), name = "scene"
}
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
print("Scene list sync display: 9 checks passed")
'''.replace('// BINDING', binding)
with tempfile.TemporaryDirectory(prefix='scene-list-sync-') as directory:
    path = Path(directory)
    (path / 'main.swift').write_text(swift)
    subprocess.run(['swiftc', str(path / 'main.swift'), '-o', str(path / 'tests')], check=True)
    subprocess.run([str(path / 'tests')], check=True)
