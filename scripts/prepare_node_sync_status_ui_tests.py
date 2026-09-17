#!/usr/bin/env python3
"""生成无账号、无云端、无蓝牙操作的真机同步刷新/Cell 复用测试工程。"""
from pathlib import Path
import importlib.util
import json
import plistlib
import runpy
import shutil
import sys
sys.dont_write_bytecode = True
repo = Path(__file__).resolve().parents[1]
out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('/tmp/NodeSyncStatusTests')
spec = importlib.util.spec_from_file_location('node_sync_tests', repo / 'scripts/check_node_sync_status_refresh.py')
helper = importlib.util.module_from_spec(spec); spec.loader.exec_module(helper)
protection_spec = importlib.util.spec_from_file_location('protection_tests', repo / 'scripts/check_space_protection_snapshot.py')
protection_helper = importlib.util.module_from_spec(protection_spec); protection_spec.loader.exec_module(protection_helper)
sys.argv = [str(repo / 'scripts/prepare_configuration_recovery_ui_tests.py'), str(out)]
runpy.run_path(sys.argv[0], run_name='__main__')
storage_source = runpy.run_path(str(repo / 'scripts/prepare_node_sync_topology_storage_tests.py'))['source']()
(out / 'StorageTests.swift').write_text(storage_source)
source = helper.production()
source = source.replace('struct Info { var groups: [Group] = [] }', 'struct Info { var groups: [Group] = []; var imageId = 1 }')
source = source.replace('final class Scene {', 'final class Scene {\n var name = "Scene 1"')
source = source.replace('final class Schedule {', '''final class Schedule {
 var name = "Schedule 1", enabled = true, weekStr = "Mo, Tu, We, Th, Fr", hour = 17, minute = 16, fadeTime = 5
 enum Action { case turnOn, turnOff, sceneRecall, noAction }
 var action = Action.turnOn
''')
source += '\nimport UIKit\n' + (repo / 'SunSmart/Common/View/AdaptiveTextView.swift').read_text()
source += '''
func SCRXFrom(_ value: CGFloat) -> CGFloat { value }
func SCRYFrom(_ value: CGFloat) -> CGFloat { value }
func FontFit(_ value: CGFloat) -> CGFloat { value }
func RGB(_ r: Int, _ g: Int, _ b: Int, _ alpha: CGFloat = 1) -> UIColor { UIColor(red: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: alpha) }
extension UILabel {
 convenience init(text: String?, textColor: UIColor) { self.init(frame: .zero); self.text = text; self.textColor = textColor }
}
let Title_Color = UIColor.black
extension UIButton {
    convenience init(normalImageName: String, target: Any?, action: Selector) {
        self.init(type: .custom); setImage(UIImage(named: normalImageName), for: .normal)
        addTarget(target, action: action, for: .touchUpInside)
    }
}
'''
source += (repo / 'SunSmart/Main/Group/View/GroupsViewCell.swift').read_text().replace('import NordicSigMeshSDK', '')
source += '''
let isIPad = false, TextBlack_Color = UIColor.black, SubText_Color = UIColor.gray, Bar_Color = UIColor.blue
let sceneImageNames = ["scene_image_1"]
extension UILabel {
 convenience init(text: String?, textColor: UIColor, fontSize: CGFloat, fontWeight: UIFont.Weight) {
  self.init(text: text, textColor: textColor); font = .systemFont(ofSize: fontSize, weight: fontWeight)
 }
}
extension UIButton {
 convenience init(target: Any?, action: Selector) { self.init(type: .custom); addTarget(target, action: action, for: .touchUpInside) }
}
'''
for relative in ['SunSmart/Main/Scene/View/SceneExecuteAnimationView.swift', 'SunSmart/Main/Scene/View/ScenesViewCell.swift', 'SunSmart/Main/Timed/View/SchedulesViewCell.swift']:
    source += (repo / relative).read_text().replace('import NordicSigMeshSDK', '')
source += '\n' + protection_helper.fixtures()
source += '''
@main final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds); window.rootViewController = TestController()
        window.makeKeyAndVisible(); self.window = window; return true
    }
}
final class TestController: UIViewController {
    let result = UILabel(), cell = GroupsViewCell(frame: CGRect(x: 24, y: 250, width: 160, height: 192))
    var started = false
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .white
        result.accessibilityIdentifier = "result"; result.text = "Running"; result.numberOfLines = 0; result.font = .systemFont(ofSize: 13)
        result.frame = CGRect(x: 24, y: 80, width: view.bounds.width - 48, height: 155)
        view.addSubview(result); view.addSubview(cell)
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated); guard !started else { return }; started = true
        Task { await self.exercise() }
    }
    func exercise() async {
        do {
            try await Task.detached { try SpaceProtectionReadSnapshotTests.run() }.value
            let sdkResult = try SyncSDKSubscriptionTests.run()
            let storageResult = try await SyncTopologyStorageTests.run()
            #if DEBUG
            print(SpaceProtectionReadSnapshotTests.report)
            print(sdkResult)
            print(storageResult)
            #endif
        } catch { fatalError("Protection/SDK fixture failed: " + String(describing: error)) }
        SyncSDKSubscriptionTests.installRefreshLookup()
        await NodeSyncStatusRefreshTests.run()
        let network = NodeSyncStatusRefreshTests.fixture(5)
        let oldGroup = network.groups[0]
        network.nodes[0].proximityLightingEnabled = false
        oldGroup.info.imageText = "Old"
        cell.group = oldGroup
        cell.prepareForReuse()
        let replacement = Group(0xC002); replacement.network = network
        replacement.info.imageText = "New"; network.groups.append(replacement)
        cell.group = replacement
        await NodeSyncStatusRefreshTests.drain { !cell.imageLabel.isHidden && cell.imageLabel.text == "New" }
        try? await Task.sleep(nanoseconds: 30_000_000)
        precondition(cell.imageView.isHidden && cell.imageLabel.text == "New", "obsolete Cell result overwrote new group")
        cell.group = oldGroup
        await NodeSyncStatusRefreshTests.drain { !cell.imageView.isHidden && cell.imageLabel.isHidden }
        precondition(cell.imageView.image?.pngData() == UIImage(named: "sync_failed_big")?.pngData(), "sync marker was not applied")
        cell.layoutIfNeeded()
        precondition(cell.imageView.bounds.width > 0 && cell.imageView.bounds.height > 0, "sync icon has no layout")
        let sceneCell = ScenesViewCell(frame: CGRect(x: 200, y: 250, width: 160, height: 192))
        let timedCell = SchedulesViewCell(frame: CGRect(x: 24, y: 470, width: view.bounds.width - 48, height: 114))
        view.addSubview(sceneCell); view.addSubview(timedCell)
        NodeSyncStatusRefresh.beginSession(owner: self)
        let oldScene = Scene(); oldScene.info.groups = [oldGroup]; oldScene.unsynced = [network.nodes[0].primaryUnicastAddress]
        MeshNetworkManager.instance.scenes = [oldScene]
        sceneCell.scene = oldScene; sceneCell.prepareForReuse()
        let newScene = Scene(); newScene.info.groups = [oldGroup]
        MeshNetworkManager.instance.scenes = [newScene]
        sceneCell.scene = newScene
        let oldSchedule = Schedule(); oldSchedule.groups = [oldGroup]; oldSchedule.syncRead = { _, _ in true }
        MeshNetworkManager.instance.schedules = [oldSchedule]
        timedCell.schedule = oldSchedule; timedCell.prepareForReuse()
        let newSchedule = Schedule(); newSchedule.groups = [oldGroup]
        MeshNetworkManager.instance.schedules = [newSchedule]
        timedCell.schedule = newSchedule
        let marker = timedCell.contentView.subviews.compactMap { $0 as? UIImageView }.first!
        await NodeSyncStatusRefreshTests.drain { marker.isHidden && sceneCell.imageView.image?.pngData() == UIImage(named: "scene_image_1")?.pngData() }
        timedCell.layoutIfNeeded(); sceneCell.layoutIfNeeded()
        precondition(marker.bounds.width > 0 && sceneCell.imageView.bounds.width > 0, "page marker has no layout")
        precondition(!timedCell.hasAmbiguousLayout && !sceneCell.hasAmbiguousLayout, "page Cell layout ambiguous")
        newSchedule.syncRead = { _, _ in true }; newScene.unsynced = oldScene.unsynced
        NodeSyncStatusGeneration.invalidate()
        timedCell.schedule = newSchedule; sceneCell.scene = newScene
        var statusDone = false
        NodeSyncStatusRefresh.request(schedule: newSchedule, owner: marker) { value in precondition(value); statusDone = true }
        await NodeSyncStatusRefreshTests.drain { statusDone }
        precondition(!marker.isHidden && sceneCell.imageView.image?.pngData() == UIImage(named: "sync_failed_big")?.pngData(), "edited page did not refresh status")
        for _ in 0..<10 {
            timedCell.schedule = newSchedule; sceneCell.scene = newScene
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        newSchedule.enabled = false; timedCell.frame.size.height = 64; timedCell.schedule = newSchedule
        timedCell.layoutIfNeeded()
        precondition(!timedCell.hasAmbiguousLayout, "disabled Timed layout ambiguous")
        NodeSyncStatusRefresh.endSession(owner: self)
        result.text = NodeSyncStatusRefreshTests.summary + "; Group/Scene/Timed Cell reuse, layout and marker PASS"
        #if DEBUG
        print(result.text!)
        #endif
        if ProcessInfo.processInfo.arguments.contains("--self-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exit(0) }
        }
    }
}
'''
(out / 'App.swift').write_text(source)
(out / 'SDKTests.swift').write_text((repo / 'Tests/Group/SyncSDKSubscriptionTests.swift').read_text())
(out / 'RecoveryUITests.swift').write_text('''import XCTest
final class RecoveryUITests: XCTestCase {
    func testBatchAndCellReuseOnDevice() {
        let app = XCUIApplication(); app.launch()
        let result = app.staticTexts["result"]
        expectation(for: NSPredicate(format: "label BEGINSWITH 'PASS:'"), evaluatedWith: result)
        waitForExpectations(timeout: 30)
        XCTAssertTrue(result.label.contains("Group/Scene/Timed Cell reuse, layout and marker PASS"))
        let text = XCTAttachment(string: result.label); text.name = "Batch measurements"; text.lifetime = .keepAlways; add(text)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Sync marker"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.terminate()
    }
}
''')
assets = out / 'Assets.xcassets'; assets.mkdir(exist_ok=True)
(assets / 'Contents.json').write_text('{"info":{"version":1}}')
for name in ['group_image_1', 'sync_failed_big', 'scene_delete', 'scene_image_1', 'schedule_tips']:
    images = list((repo / 'SunSmart/Assets.xcassets').rglob(name + '.imageset'))
    if images: shutil.copytree(images[0], assets / images[0].name, dirs_exist_ok=True)
shutil.copytree(repo / 'Pods/SnapKit/Sources', out / 'SnapKit', dirs_exist_ok=True, copy_function=shutil.copyfile)
project_path = out / 'RecoveryLayout.xcodeproj/project.pbxproj'
project = plistlib.loads(project_path.read_bytes()); objects = project['objects']
def obj(isa, **kwargs):
    key = f'{max(int(x,16) for x in objects)+1:024X}'; objects[key] = dict(isa=isa, **kwargs); return key
app_target = next(v for v in objects.values() if v.get('isa') == 'PBXNativeTarget' and v.get('name') == 'RecoveryLayout')
sources = next(objects[k] for k in app_target['buildPhases'] if objects[k]['isa'] == 'PBXSourcesBuildPhase')
resources = next(objects[k] for k in app_target['buildPhases'] if objects[k]['isa'] == 'PBXResourcesBuildPhase')
framework_key = obj('PBXFrameworksBuildPhase', buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0)
app_target['buildPhases'].append(framework_key)
frameworks = objects[framework_key]
resolved = json.loads((repo / 'SunSmart.xcworkspace/xcshareddata/swiftpm/Package.resolved').read_text())
revision = next(pin['state']['revision'] for pin in resolved['pins'] if pin['identity'] == 'nordic-sig-mesh-sdk')
package = obj('XCRemoteSwiftPackageReference', repositoryURL='git@gitee.com:sunricher-i-os/nordic-sig-mesh-sdk.git',
              requirement={'kind': 'revision', 'revision': revision})
objects[project['rootObject']].setdefault('packageReferences', []).append(package)
product = obj('XCSwiftPackageProductDependency', package=package, productName='NordicSigMeshSDK')
app_target.setdefault('packageProductDependencies', []).append(product)
frameworks['files'].append(obj('PBXBuildFile', productRef=product))
ref = obj('PBXFileReference', lastKnownFileType='sourcecode.swift', path='SDKTests.swift', sourceTree='<group>')
sources['files'].append(obj('PBXBuildFile', fileRef=ref))
ref = obj('PBXFileReference', lastKnownFileType='sourcecode.swift', path='StorageTests.swift', sourceTree='<group>')
sources['files'].append(obj('PBXBuildFile', fileRef=ref))
for source in sorted((out / 'SnapKit').glob('*.swift')):
    ref = obj('PBXFileReference', lastKnownFileType='sourcecode.swift', path=str(source.relative_to(out)), sourceTree='<group>')
    sources['files'].append(obj('PBXBuildFile', fileRef=ref))
ref = obj('PBXFileReference', lastKnownFileType='folder.assetcatalog', path='Assets.xcassets', sourceTree='<group>')
resources['files'].append(obj('PBXBuildFile', fileRef=ref))
for value in objects.values():
    if value.get('isa') == 'XCBuildConfiguration':
        settings = value['buildSettings']
        settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = 'DEBUG SUNSMART_PERFORMANCE'
        if value.get('name') == 'Release':
            settings['SWIFT_OPTIMIZATION_LEVEL'] = '-O'
            settings['SWIFT_COMPILATION_MODE'] = 'wholemodule'
            settings['ENABLE_TESTABILITY'] = 'NO'
            settings['ENABLE_DEBUG_DYLIB'] = 'NO'
        if 'PRODUCT_BUNDLE_IDENTIFIER' in settings:
            settings['PRODUCT_BUNDLE_IDENTIFIER'] = settings['PRODUCT_BUNDLE_IDENTIFIER'].replace('recovery-layout', 'node-sync-status')
project_path.write_bytes(plistlib.dumps(project))
print(out)
