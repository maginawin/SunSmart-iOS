#!/usr/bin/env python3
"""生成隔离的真机布局测试工程，使用生产 Cell、约束和可见行刷新方法。"""
from pathlib import Path
import importlib.util
import plistlib
import re
import runpy
import shutil
import sys

sys.dont_write_bytecode = True
repo = Path(__file__).resolve().parents[1]
out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('/tmp/SyncDevicesRowLayout')
spec = importlib.util.spec_from_file_location('row_tests', repo / 'scripts/check_sync_devices_row_display.py')
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)
sys.argv = [str(repo / 'scripts/prepare_configuration_recovery_ui_tests.py'), str(out)]
runpy.run_path(sys.argv[0], run_name='__main__')
section = helper.section
models = helper.STUB_MODELS + helper.model_source()
macro = (repo / 'SunSmart/Common/Macro/MacroDefinition.swift').read_text()
support = section(macro, 'var SCREEN_WIDTH:', '// 检查当前首选语言是否是中文')
support += '\nfunc RGB(_ r: Int, _ g: Int, _ b: Int) -> UIColor { UIColor(red: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: 1) }\n'
support += 'let TextBlack_Color = RGB(30, 35, 41), Red_Color = RGB(235, 78, 78), Line_Color = RGB(243, 243, 243)\n'
support += 'extension String { var localizedString: String { NSLocalizedString(self, comment: "") } }\n'
support += (repo / 'SunSmart/Common/Extension/UILabel+Extension.swift').read_text()
button = (repo / 'SunSmart/Common/Extension/UIButton+Extension.swift').read_text()
support += 'extension UIButton {\n' + section(button, '    convenience init(', '    func setImagePosition(') + '\n}\n'
support += (repo / 'SunSmart/Common/Extension/CALayer+Animations.swift').read_text()
views = '\n'.join((repo / 'SunSmart/Main/Space/View' / name).read_text() for name in ['SyncDeviceViewCell.swift', 'SyncDevicesGroupViewCell.swift', 'SyncDeviceStepViewCell.swift'])
controller = (repo / 'SunSmart/Main/Space/Controller/SyncDevicesViewController.swift').read_text()
refresh = section(controller, '    private func refreshVisibleSyncCells()', '    private func setupUI()')
app = '''import UIKit
@main final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = LayoutController()
        window?.makeKeyAndVisible()
        return true
    }
}
struct Section { let rowModels: [SyncCellModel] }
final class LayoutController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    var tableView: UITableView! = UITableView()
    let syncDisplayContext = SyncDevicesDisplayContext()
    var sections: [Section] = []
    let result = UILabel()
    let device = SyncDevicesModel(name: "Device 1", address: 1)
    var group: SyncDevicesGroupModel!
    var step: SyncDeviceStepModel!
    var started = false
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        let tasks = (0..<12).map { _ in SyncDeviceStepTaskModel() }
        step = SyncDeviceStepModel(type: "Profile", state: .wait, tasks: tasks)
        step.parentDeviceModel = device
        tasks.forEach { $0.parentStepModel = step }
        device.steps = [step]
        group = SyncDevicesGroupModel(groupName: "Group 1", groupAddress: 0xC000, deviceModels: [device])
        device.parentGroupModel = group
        group.isShow = true
        sections = [Section(rowModels: [group, device, step])]
        tableView.register(SyncDeviceViewCell.self, forCellReuseIdentifier: "device")
        tableView.register(SyncDevicesGroupViewCell.self, forCellReuseIdentifier: "group")
        tableView.register(SyncDeviceStepViewCell.self, forCellReuseIdentifier: "step")
        tableView.dataSource = self; tableView.delegate = self
        tableView.separatorStyle = .none
        result.accessibilityIdentifier = "result"
        result.text = "Running"; result.textColor = .black
        view.addSubview(tableView); view.addSubview(result)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        result.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            result.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            result.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            tableView.topAnchor.constraint(equalTo: result.bottomAnchor, constant: 12),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !started else { return }; started = true
        Task { @MainActor in await exercise() }
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { sections[section].rowModels.count }
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { SCRYFrom(44) }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.row {
        case 0:
            let cell = tableView.dequeueReusableCell(withIdentifier: "group", for: indexPath) as! SyncDevicesGroupViewCell
            cell.configure(with: group, displayState: syncDisplayContext.state(for: group)); return cell
        case 1:
            let cell = tableView.dequeueReusableCell(withIdentifier: "device", for: indexPath) as! SyncDeviceViewCell
            cell.configure(with: device, displayState: syncDisplayContext.state(for: device)); return cell
        default:
            let cell = tableView.dequeueReusableCell(withIdentifier: "step", for: indexPath) as! SyncDeviceStepViewCell
            cell.stepModel = step; cell.topLineView.isHidden = true; cell.bottomLineView.isHidden = true; return cell
        }
    }
    func verify(_ value: Bool, _ reason: String) {
        if !value { result.text = "FAIL: " + reason; fatalError(reason) }
    }
    func inspectRunning() {
        tableView.layoutIfNeeded()
        let cell = tableView.cellForRow(at: IndexPath(row: 1, section: 0)) as! SyncDeviceViewCell
        let groupCell = tableView.cellForRow(at: IndexPath(row: 0, section: 0)) as! SyncDevicesGroupViewCell
        let stepCell = tableView.cellForRow(at: IndexPath(row: 2, section: 0)) as! SyncDeviceStepViewCell
        verify(!cell.arrowImageView.isHidden && cell.stateImageView.isHidden, "Device icon flicker")
        verify(groupCell.stateImageView.isHidden, "Group waiting icon flicker")
        verify(!stepCell.progressLabel.isHidden, "Progress flicker")
        verify(!cell.arrowImageView.hasAmbiguousLayout, "Arrow ambiguous")
        verify(cell.bounds.contains(cell.arrowImageView.frame), "Arrow outside cell")
        verify(stepCell.progressLabel.frame.minX >= 0, "Progress outside cell")
        verify(abs(cell.arrowImageView.center.y - cell.bounds.midY) < 1, "Arrow not centered")
        verify(stepCell.progressLabel.frame.maxX <= stepCell.stateImageView.frame.minX, "Progress overlaps status")
    }
    func pause() async { try? await Task.sleep(nanoseconds: 120_000_000) }
    func exercise() async {
        let run = UUID(); syncDisplayContext.beginRun(run)
        tableView.reloadData(); tableView.layoutIfNeeded()
        for index in step.tasks.indices {
            let task = step.tasks[index]
            task.state = .inSettings; syncDisplayContext.taskDidStart(task, run: run)
            device.isShow = true; refreshVisibleSyncCells(); await pause(); inspectRunning()
            let cell = tableView.cellForRow(at: IndexPath(row: 1, section: 0))!
            task.state = index == 0 ? .failed : .successful
            refreshVisibleSyncCells(); await pause()
            if index < 11 {
                inspectRunning()
                verify(tableView.cellForRow(at: IndexPath(row: 1, section: 0)) === cell, "Cell replaced")
            }
        }
        device.isFineshed = true; group.isFineshed = true; step.isFineshed = true
        refreshVisibleSyncCells(); await pause()
        let retry = UUID(); step.tasks[0].state = .wait
        device.isFineshed = false; group.isFineshed = false; step.isFineshed = false
        syncDisplayContext.beginRun(retry); refreshVisibleSyncCells(); await pause()
        step.tasks[0].state = .inSettings
        syncDisplayContext.taskDidStart(step.tasks[0], run: retry); refreshVisibleSyncCells()
        // 重新绑定模拟离屏返回，显示上下文必须保持有效。
        tableView.reloadData(); await pause(); inspectRunning()
        device.isShow = false; refreshVisibleSyncCells(); await pause(); inspectRunning()
        result.text = "PASS: stable icons and layout"
    }
'''
app += refresh + '\n}\n' + models + support + views
(out / 'App.swift').write_text(app)
(out / 'RecoveryUITests.swift').write_text('''import XCTest
final class SyncRowUITests: XCTestCase {
    func testPortrait() { exercise(.portrait) }
    func testLandscape() { exercise(.landscapeLeft) }
    private func exercise(_ orientation: UIDeviceOrientation) {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = orientation
        let app = XCUIApplication(); app.launch()
        let result = app.staticTexts["result"]
        let success = NSPredicate(format: "label == %@", "PASS: stable icons and layout")
        expectation(for: success, evaluatedWith: result)
        waitForExpectations(timeout: 20)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Sync row layout"; attachment.lifetime = .keepAlways; add(attachment)
        app.terminate()
    }
}
''')
assets = out / 'Assets.xcassets'; assets.mkdir(exist_ok=True)
(assets / 'Contents.json').write_text('{"info":{"author":"xcode","version":1}}')
for name in sorted(set(re.findall(r'"([a-z][a-z0-9_]+)"', views))):
    sources = list((repo / 'SunSmart/Assets.xcassets').rglob(name + '.imageset'))
    if sources:
        shutil.copytree(sources[0], assets / sources[0].name, dirs_exist_ok=True)
shutil.copytree(repo / 'Pods/SnapKit/Sources', out / 'SnapKit', dirs_exist_ok=True)
project_path = out / 'RecoveryLayout.xcodeproj/project.pbxproj'
project = plistlib.loads(project_path.read_bytes()); objects = project['objects']
def obj(isa, **kwargs):
    key = f'{max(int(x, 16) for x in objects) + 1:024X}'
    objects[key] = dict(isa=isa, **kwargs); return key
app_target = next(v for v in objects.values() if v.get('isa') == 'PBXNativeTarget' and v.get('name') == 'RecoveryLayout')
source_phase = next(objects[k] for k in app_target['buildPhases'] if objects[k]['isa'] == 'PBXSourcesBuildPhase')
resource_phase = next(objects[k] for k in app_target['buildPhases'] if objects[k]['isa'] == 'PBXResourcesBuildPhase')
for source in sorted((out / 'SnapKit').glob('*.swift')):
    ref = obj('PBXFileReference', lastKnownFileType='sourcecode.swift', path=str(source.relative_to(out)), sourceTree='<group>')
    source_phase['files'].append(obj('PBXBuildFile', fileRef=ref))
ref = obj('PBXFileReference', lastKnownFileType='folder.assetcatalog', path='Assets.xcassets', sourceTree='<group>')
resource_phase['files'].append(obj('PBXBuildFile', fileRef=ref))
for value in objects.values():
    if value.get('isa') == 'XCBuildConfiguration':
        settings = value['buildSettings']
        if 'PRODUCT_BUNDLE_IDENTIFIER' in settings:
            settings['PRODUCT_BUNDLE_IDENTIFIER'] = settings['PRODUCT_BUNDLE_IDENTIFIER'].replace('recovery-layout', 'sync-row-layout')
project_path.write_bytes(plistlib.dumps(project))
print(out)
