"""Execute production detail binding and snapshot lifecycle with controlled async reads."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
page = (root / 'SunSmart/Main/Scene/Controller/SceneViewController.swift').read_text()
configure = page[page.index('    private func configure('):page.index('    @objc private func close()')].replace('private func', 'func')
reader = (root / 'SunSmart/Common/Data/SpacePageSyncRead.swift').read_text()
display = reader[reader.index('final class SceneGroupDisplayState'):reader.index('private extension NodeSyncReadContext', reader.index('final class SceneGroupDisplayState'))]
swift = r'''
import Foundation
struct SceneData { var sceneNumber = 1; init() {}; init(data: SceneData) { self = data } }
final class Group { struct Info { var sceneExecuteDatas = [SceneData()] }; var info = Info() }
final class Scene { let number = 1 }
struct SceneGroupSyncSnapshot {
    static var generation = 0
    private let revision = generation
    var isCurrent: Bool { revision == Self.generation }
    var needsSync: Set<ObjectIdentifier> = []
}
enum NodeSyncStatusRefresh {
    static var callbacks: [(SceneGroupSyncSnapshot?) -> Void] = []
    static func cancel(owner: AnyObject) {}
    static func requestSceneGroups(scene: Scene, owner: AnyObject, completion: @escaping (SceneGroupSyncSnapshot?) -> Void) { callbacks.append(completion) }
}
// DISPLAY
final class SceneGroupsViewCell {
    var warning = false
    func updateData(group: Group, sceneData: SceneData?, appearance: Int?, needsSync: Bool) { warning = needsSync }
}
final class Page {
    let scene = Scene(), syncDisplay = SceneGroupDisplayState()
    let appearances: [ObjectIdentifier: Int] = [:]
// CONFIGURE
}
let page = Page(), first = Group(), second = Group()
let a = SceneGroupsViewCell(), b = SceneGroupsViewCell()
func check(_ first: Bool, _ second: Bool, _ message: String) {
    page.configure(a, group: globals.0); page.configure(b, group: globals.1)
    precondition(a.warning == first && b.warning == second, message)
}
let globals = (first, second)
page.syncDisplay.refresh(scene: page.scene) {}
check(false, false, "pending initial read must not warn every group")
NodeSyncStatusRefresh.callbacks.last!(nil)
check(false, false, "unavailable read is not confirmed work")
page.syncDisplay.refresh(scene: page.scene) {}
NodeSyncStatusRefresh.callbacks.last!(SceneGroupSyncSnapshot(needsSync: [ObjectIdentifier(first)]))
check(true, false, "only group with confirmed work should warn")
page.syncDisplay.cancel()
SceneGroupSyncSnapshot.generation += 1
page.syncDisplay.refresh(scene: page.scene) {}
check(false, false, "recheck after invalidation must not warn all members")
let oldCallback = NodeSyncStatusRefresh.callbacks.last!
page.syncDisplay.cancel()
page.syncDisplay.refresh(scene: page.scene) {}
oldCallback(SceneGroupSyncSnapshot(needsSync: [ObjectIdentifier(first), ObjectIdentifier(second)]))
check(false, false, "cancelled read must not publish obsolete warnings")
NodeSyncStatusRefresh.callbacks.last!(SceneGroupSyncSnapshot())
check(false, false, "successful sync leaves both groups normal")
print("Scene detail sync display: 6 checks passed")
'''.replace('// DISPLAY', display).replace('// CONFIGURE', configure)
with tempfile.TemporaryDirectory(prefix='scene-detail-sync-') as directory:
    path = Path(directory)
    (path / 'main.swift').write_text(swift)
    subprocess.run(['swiftc', str(path / 'main.swift'), '-o', str(path / 'tests')], check=True)
    subprocess.run([str(path / 'tests')], check=True)
