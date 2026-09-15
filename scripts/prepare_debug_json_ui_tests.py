#!/usr/bin/env python3
"""Build a physical-device harness using the real menu, cells and Debug exporter.
Fixture models isolate user databases and networking; no business app is replaced.
"""
from pathlib import Path
import plistlib, runpy, shutil, sys
repo=Path(__file__).resolve().parents[1]
out=Path(sys.argv[1]) if len(sys.argv)>1 else Path('/tmp/DebugJSONLayout')
sys.argv=[str(repo/'scripts/prepare_configuration_recovery_ui_tests.py'),str(out)]
runpy.run_path(sys.argv[0],run_name='__main__')
app=(repo/'Tests/Cloud/DebugCloudJSONFixtures.swift').read_text()
app+='''
@main final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UINavigationController(rootViewController: ExportController())
        window.makeKeyAndVisible(); self.window = window; return true
    }
}
final class ExportController: UIViewController {
    let site = SiteData(), space = SpaceData()
    let debugJSONExporter = DebugCloudJSONExporter()
    let outcome = UILabel()
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Export JSON Test"; view.backgroundColor = .systemBackground
        let role = ProcessInfo.processInfo.arguments.contains("visitor") ? Permission.visitor : (ProcessInfo.processInfo.arguments.contains("editor") ? .editor : .owner)
        site.permission = role; space.permission = role; site.spaces = [space]
        if ProcessInfo.processInfo.arguments.contains("protected") {
            space.unavailable = true
            SpaceConfigurationSafety.unavailable.insert(space.id)
        }
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Menu", style: .plain, target: self, action: #selector(openMenu))
        outcome.accessibilityIdentifier = "outcome"; outcome.text = "Starting"
        outcome.frame = CGRect(x: 20, y: 160, width: 350, height: 50); view.addSubview(outcome)
        Task { @MainActor in
            do { try await runSnapshotTests(); outcome.text = "Snapshot tests passed" }
            catch { preconditionFailure("Snapshot tests failed: \\(error)") }
        }
    }
    @objc func openMenu() {
        if ProcessInfo.processInfo.arguments.contains("site") { siteMenu() } else { spaceMenu() }
    }
    func finishMenu(_ items: [MenuPopView.MenuItem], minimum: CGFloat) {
        let width = DebugCloudJSONExporter.menuWidth(items: items, minimum: minimum)
        MenuPopView.show(items: items, anchorPoint: CGPoint(x: view.bounds.maxX - 30, y: view.safeAreaInsets.top), menuWidth: width)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.auditMenu() }
    }
    func auditMenu() {
        let window = UIApplication.shared.keyWindow()
        func check(_ view: UIView) {
            if let cell = view as? CustomTableViewCell {
                let label = cell.titleLabel!
                precondition(!label.hasAmbiguousLayout)
                let rect = label.convert(label.bounds, to: window)
                let cellRect = cell.contentView.convert(cell.contentView.bounds, to: window)
                precondition(window.bounds.contains(rect), "Label outside screen: \\(rect)")
                precondition(cellRect.insetBy(dx: -0.5, dy: -0.5).contains(rect), "Clipped label: \\(label.text ?? "")")
                precondition(label.bounds.width + 1 >= label.intrinsicContentSize.width)
            }
            for child in view.subviews { check(child) }
        }
        check(window)
        outcome.text = "Layout passed"
    }
    override func present(_ controller: UIViewController, animated: Bool, completion: (() -> Void)? = nil) {
        if controller is UIActivityViewController {
            outcome.text = "Share presented"
            controller.view.accessibilityIdentifier = "json-share"
        }
        super.present(controller, animated: animated, completion: completion)
    }
'''
for kind,titles,minimum in [('site',['edit_site','delete_site','share_authoority'],154),('space',['edit','delete','share'],108)]:
    text=(repo/f'SunSmart/Main/{kind.title()}/Controller/{kind.title()}ViewController.swift').read_text()
    start=text.index('        #if DEBUG\n        if DebugCloudJSONExporter.canExport(',text.index('    @objc private func moreClick()'))
    end=text.index('        #endif',start)+len('        #endif')
    app+=f'    func {kind}Menu() {{\n        var items: [MenuPopView.MenuItem] = []\n'
    app+='        for key in '+repr(titles).replace("'",'"')+' { items.append(.init(icon: UIImage(named: "menu_share"), title: key.localizedString, tapItemBack: nil)) }\n'
    app+=text[start:end]+'\n'
    extras=['transfer_site','restore_device','Firmware_update'] if kind=='site' else ['debug','unbind']
    app+='        for key in '+repr(extras).replace("'",'"')+' { items.append(.init(icon: UIImage(named: "menu_share"), title: key.localizedString, tapItemBack: nil)) }\n'
    app+=f'        finishMenu(items, minimum: SCRXFrom({minimum}))\n    }}\n'
app+='}\n'
(out/'App.swift').write_text(app)
shutil.copyfile(repo/'Tests/Cloud/DebugCloudJSONUITests.swift',out/'RecoveryUITests.swift')
assets=out/'Assets.xcassets';assets.mkdir(exist_ok=True)
(assets/'Contents.json').write_text('{"info":{"author":"xcode","version":1}}')
for name in ['menu_bubble','menu_share','arrow_right']:
    source=next((repo/'SunSmart/Assets.xcassets').rglob(name+'.imageset'))
    shutil.copytree(source,assets/source.name,dirs_exist_ok=True)
shutil.copytree(repo/'Pods/SnapKit/Sources',out/'SnapKit',dirs_exist_ok=True,copy_function=shutil.copyfile)
sources=[]
for path in ['SunSmart/Common/View/MenuPopView.swift','SunSmart/Common/View/CustomTableViewCell.swift','SunSmart/Common/Cloud/DebugCloudJSONExporter.swift','SunSmart/Common/Cloud/DebugCloudJSONFile.swift']:
    source=repo/path;target=out/source.name
    target.write_text(source.read_text().replace('import SnapKit',''))
    sources.append(target)
sources+=sorted((out/'SnapKit').glob('*.swift'))
project_path=out/'RecoveryLayout.xcodeproj/project.pbxproj'
project=plistlib.loads(project_path.read_bytes()); objects=project['objects']
def obj(isa,**kwargs):
    key=f'{max(int(x,16) for x in objects)+1:024X}';objects[key]=dict(isa=isa,**kwargs);return key
app_target=next(v for v in objects.values() if v.get('isa')=='PBXNativeTarget' and v.get('name')=='RecoveryLayout')
source_phase=next(objects[k] for k in app_target['buildPhases'] if objects[k]['isa']=='PBXSourcesBuildPhase')
resource_phase=next(objects[k] for k in app_target['buildPhases'] if objects[k]['isa']=='PBXResourcesBuildPhase')
for source in sources:
    ref=obj('PBXFileReference',lastKnownFileType='sourcecode.swift',path=str(source.relative_to(out)),sourceTree='<group>')
    source_phase['files'].append(obj('PBXBuildFile',fileRef=ref))
ref=obj('PBXFileReference',lastKnownFileType='folder.assetcatalog',path='Assets.xcassets',sourceTree='<group>')
resource_phase['files'].append(obj('PBXBuildFile',fileRef=ref))
for value in objects.values():
    if value.get('isa')=='XCBuildConfiguration':
        settings=value['buildSettings'];settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS']='DEBUG'
        if 'PRODUCT_BUNDLE_IDENTIFIER' in settings:
            settings['PRODUCT_BUNDLE_IDENTIFIER']=settings['PRODUCT_BUNDLE_IDENTIFIER'].replace('recovery-layout','debug-json-layout')
project_path.write_bytes(plistlib.dumps(project))
print(out)
