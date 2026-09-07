#!/usr/bin/env python3
"""Prepare a physical-device UI harness using production Space status/rendering code."""
from pathlib import Path
import plistlib
import runpy
import shutil
import sys

repo = Path(__file__).resolve().parents[1]
out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('/tmp/CloudSyncLayout')
sys.argv = [str(repo / 'scripts/prepare_configuration_recovery_ui_tests.py'), str(out)]
runpy.run_path(sys.argv[0], run_name='__main__')
def section(text, start, end): return text[text.index(start):text.index(end, text.index(start))]
controller = (repo / 'SunSmart/Main/Space/Controller/SpaceViewController.swift').read_text()
status = section(controller, '    private func updateSyncState()', '    private func showConfigurationRecovery()')
extension = (repo / 'SunSmart/Common/Extension/UIViewController+Extension.swift').read_text()
render = section(extension, '    func showNavigationBarLoading()', '    func pushDeviceInformationController(')
nav = section(extension, 'extension UINavigationController {', '    /// 设置导航条颜色') + '\n}\n'
animations = (repo / 'SunSmart/Common/Extension/CALayer+Animations.swift').read_text()
rotation = section(animations, '    func addRotationAnimation(', '    /// 添加缩放动画')
app = (out / 'App.swift').read_text().replace('window.rootViewController = RecoveryController()',
    'window.rootViewController = ProcessInfo.processInfo.arguments.contains("sync-status") ? UINavigationController(rootViewController: SpaceSyncStatusController()) : RecoveryController()')
app = app.replace('final class SpaceData {', 'final class SpaceData {\n    var showSyncCloudError: TestError? { TestError() }')
app = app.replace('enum SpaceConfigurationSafety {', '''enum SpaceConfigurationSafety {
    static func isBlocked(_ space: SpaceData) -> Bool { false }
    static func hasPendingUpload(_ space: SpaceData) -> Bool { false }
    static func requiresConfigurationReview(_ space: SpaceData) -> Bool { false }
''')
app += '''
struct TestError { var localizedDescription: String { "Test failure" } }
enum CloudState { case wait, inProgress, successful, failure }
final class CloudHandle { var state = CloudState.wait }
final class CloudSynchronizationManager {
    static let shared = CloudSynchronizationManager()
    let handle = CloudHandle()
    func getSpaceCurrentSyncState(_ space: SpaceData) -> CloudHandle? { handle }
}
struct SRAlertAction {
    static let cancelAction = SRAlertAction(title: "Cancel", actionHandler: { _ in })
    init(title: String, actionHandler: @escaping (Int) -> Void) {}
}
final class SRAlertView {
    init(title: String, message: String, actions: [SRAlertAction]) {}
    func show() {}
}
extension UIView { var x: CGFloat { frame.origin.x } }
func SCRXFrom(_ x: CGFloat) -> CGFloat {
    x * UIScreen.main.bounds.width / (UIDevice.current.userInterfaceIdiom == .pad ? 834 : 375)
}
final class SpaceSyncStatusController: UIViewController {
    let space = SpaceData()
    enum SyncLevel { case promptly }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Test Space"
        view.backgroundColor = .systemBackground
        let stack = UIStackView()
        stack.axis = .vertical; stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        for (index, title) in ["Failure", "Waiting", "Uploading", "Success"].enumerated() {
            let button = UIButton(type: .system)
            button.tag = index; button.setTitle(title, for: .normal)
            button.addTarget(self, action: #selector(changeState(_:)), for: .touchUpInside)
            stack.addArrangedSubview(button)
        }
        view.addSubview(stack)
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)])
    }
    @objc private func changeState(_ sender: UIButton) {
        CloudSynchronizationManager.shared.handle.state = [.failure, .wait, .inProgress, .successful][sender.tag]
        updateSyncState()
        navigationController?.view.layoutIfNeeded()
        guard let image = navigationController?.stateImageView else { return }
        image.isAccessibilityElement = true
        image.accessibilityIdentifier = "cloud-state"
        image.accessibilityLabel = image.layer.animation(forKey: "loading") != nil ? "Loading" : sender.currentTitle
    }
    func showConfigurationRecovery() {}
    func syncSpace(level: SyncLevel) {}
'''
app += status + '\n}\nextension UIViewController {\n' + render
app += '\n    enum NavigationBarState { case loading, successful, failure }\n}\n' + nav
app += '\nextension CALayer {\n' + rotation + '\n}\n'
(out / 'App.swift').write_text(app)
tests = (out / 'RecoveryUITests.swift').read_text()
tests += '''
final class CloudStatusUITests: XCTestCase {
    func testStateTransitionsPortrait() { exercise(landscape: false) }
    func testStateTransitionsLandscape() { exercise(landscape: true) }
    private func exercise(landscape: Bool) {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        let app = XCUIApplication(); app.launchArguments = ["sync-status"]; app.launch()
        for (action, expected) in [("Failure", "Failure"), ("Waiting", "Loading"), ("Uploading", "Loading"), ("Success", "Success")] {
            app.buttons[action].tap()
            let indicator = app.images["cloud-state"]
            XCTAssertTrue(indicator.waitForExistence(timeout: 3))
            XCTAssertEqual(indicator.label, expected)
            XCTAssertGreaterThan(indicator.frame.width, 0)
            XCTAssertTrue(app.navigationBars.firstMatch.frame.contains(indicator.frame))
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "cloud-\\(action)-\\(landscape)"; attachment.lifetime = .keepAlways
            add(attachment)
        }
        app.terminate()
    }
}
'''
(out / 'RecoveryUITests.swift').write_text(tests)
assets = out / 'Assets.xcassets'; assets.mkdir(exist_ok=True)
(assets / 'Contents.json').write_text('{"info":{"author":"xcode","version":1}}')
for name in ['sync_loading_small', 'sync_success_small', 'cloud_sync_failed']:
    source = next((repo / 'SunSmart/Assets.xcassets').rglob(name + '.imageset'))
    shutil.copytree(source, assets / source.name, dirs_exist_ok=True)
shutil.copytree(repo / 'Pods/SnapKit/Sources', out / 'SnapKit', dirs_exist_ok=True)
project_path = out / 'RecoveryLayout.xcodeproj/project.pbxproj'
project = plistlib.loads(project_path.read_bytes()); objects = project['objects']
def obj(isa, **kwargs):
    key = f'{max(int(x, 16) for x in objects) + 1:024X}'
    objects[key] = dict(isa=isa, **kwargs); return key
app_target = next(v for v in objects.values() if v.get('isa') == 'PBXNativeTarget' and v.get('name') == 'RecoveryLayout')
source_phase = next(objects[key] for key in app_target['buildPhases'] if objects[key]['isa'] == 'PBXSourcesBuildPhase')
resource_phase = next(objects[key] for key in app_target['buildPhases'] if objects[key]['isa'] == 'PBXResourcesBuildPhase')
for source in sorted((out / 'SnapKit').glob('*.swift')):
    ref = obj('PBXFileReference', lastKnownFileType='sourcecode.swift', path=str(source.relative_to(out)), sourceTree='<group>')
    source_phase['files'].append(obj('PBXBuildFile', fileRef=ref))
ref = obj('PBXFileReference', lastKnownFileType='folder.assetcatalog', path='Assets.xcassets', sourceTree='<group>')
resource_phase['files'].append(obj('PBXBuildFile', fileRef=ref))
for value in objects.values():
    if value.get('isa') == 'XCBuildConfiguration':
        settings = value['buildSettings']
        if 'PRODUCT_BUNDLE_IDENTIFIER' in settings:
            settings['PRODUCT_BUNDLE_IDENTIFIER'] = settings['PRODUCT_BUNDLE_IDENTIFIER'].replace('recovery-layout', 'cloud-sync-layout')
project_path.write_bytes(plistlib.dumps(project))
print(out)
