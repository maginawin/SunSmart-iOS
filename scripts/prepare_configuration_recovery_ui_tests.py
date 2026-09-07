#!/usr/bin/env python3
"""Prepare an isolated UIKit UI-test app from the production recovery menu.

No Mesh SDK, account, network or user database is linked. Run the generated
scheme on an explicitly selected physical device; never use a simulator.
"""
from pathlib import Path
import plistlib
import shutil
import sys

repo = Path(__file__).resolve().parents[1]
out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('/tmp/SpaceRecoveryLayout')
out.mkdir(parents=True, exist_ok=True)
controller = (repo / 'SunSmart/Main/Space/Controller/SpaceViewController.swift').read_text()
start = controller.index('    private func showConfigurationRecovery()')
end = controller.index('    private func reloadConfigurationFromCloud()', start)
methods = controller[start:end]
app = '''import UIKit
extension String { var localizedString: String { NSLocalizedString(self, comment: "") } }
final class SpaceData {
    enum Permission { case owner, editor, visitor }
    let disableEditorPermission = false, requiresPasswordVerification = false
    let permission = Permission.owner
    func export(allowsProtectedInspection: Bool) async -> [String: Any]? {
        ProcessInfo.processInfo.arguments.contains("complete-local") ? [:] : nil
    }
}
enum DevicePermanentDeletionContext { static func resume(space: SpaceData) {} }
enum SpaceConfigurationSafety {
    struct Review {
        var message: String { String(format: "configuration_repair_preview".localizedString, 0, 4, 8) }
    }
    static func referenceRepairReview(_ space: SpaceData) async -> Review? { Review() }
    static func applyReferenceRepair(_ space: SpaceData, review: Review) async -> Bool { true }
    static func authorizeLocalRecovery(_ space: SpaceData, reviewed: [String: Any]) async -> Bool { true }
}
enum XWHUDManager {
    static func showCustomHUD(withMessage: String?, isWindow: Bool) {}
    static func hide() {}
    static func showErrorTipHUD(_ message: String) { print("ERROR: " + message) }
}
@main final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = RecoveryController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}
final class RecoveryController: UIViewController {
    let space = SpaceData()
    let outcome = UILabel()
    enum SyncLevel { case promptly }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let button = UIButton(type: .system)
        button.setTitle("Open recovery", for: .normal)
        button.accessibilityIdentifier = "open-recovery"
        button.addTarget(self, action: #selector(openRecovery), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        outcome.translatesAutoresizingMaskIntoConstraints = false
        outcome.accessibilityIdentifier = "outcome"
        outcome.text = "Waiting"
        view.addSubview(button); view.addSubview(outcome)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            outcome.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            outcome.topAnchor.constraint(equalTo: button.bottomAnchor, constant: 20)
        ])
    }
    @objc private func openRecovery() { showConfigurationRecovery() }
    func reloadConfigurationFromCloud() { outcome.text = "Reload requested" }
    func reloadData() {}
    func syncSpace(level: SyncLevel) { outcome.text = "Repair accepted" }
    func presentProximityLightingRepairSyncIfNeeded() {}
'''
(out / 'App.swift').write_text(app + methods + '\n}\n')
(out / 'RecoveryUITests.swift').write_text('''import XCTest
final class RecoveryUITests: XCTestCase {
    func testEnglishPortraitRepairAndCancel() { exercise(language: "en", landscape: false) }
    func testEnglishLandscapeRepairAndCancel() { exercise(language: "en", landscape: true) }
    func testChinesePortraitRepairAndCancel() { exercise(language: "zh-Hans", landscape: false) }
    func testChineseLandscapeRepairAndCancel() { exercise(language: "zh-Hans", landscape: true) }
    private func exercise(language: String, landscape: Bool) {
        continueAfterFailure = false
        let chinese = language == "zh-Hans"
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(\\(language))", "-AppleLocale", chinese ? "zh_CN" : "en_US"]
        app.launch()
        app.buttons["open-recovery"].tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertEqual(alert.buttons.count, 3, "Cancel, Reload, and Repair must all remain available")
        let repair = alert.buttons[chinese ? "检查本地修复" : "Review local repair"]
        XCTAssertTrue(repair.isHittable)
        attach(app, name: "menu-\\(language)-\\(landscape)")
        repair.tap()
        let confirm = app.alerts.firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertEqual(confirm.buttons.count, 2)
        let cancel = confirm.buttons.matching(identifier: chinese ? "取消" : "CANCEL").firstMatch
        XCTAssertTrue(cancel.isHittable)
        attach(app, name: "preview-\\(language)-\\(landscape)")
        cancel.tap()
        XCTAssertEqual(app.staticTexts["outcome"].label, "Waiting")
        app.buttons["open-recovery"].tap()
        app.alerts.buttons[chinese ? "检查本地修复" : "Review local repair"].tap()
        let accept = app.alerts.buttons[chinese ? "确认" : "CONFIRM"]
        XCTAssertTrue(accept.waitForExistence(timeout: 5))
        XCTAssertTrue(accept.isHittable)
        accept.tap()
        XCTAssertTrue(app.staticTexts["Repair accepted"].waitForExistence(timeout: 5))
        app.terminate()
    }
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
''')
info = {'CFBundleDisplayName': 'Recovery Layout Test', 'CFBundleIdentifier': '$(PRODUCT_BUNDLE_IDENTIFIER)',
        'CFBundleExecutable': '$(EXECUTABLE_NAME)', 'CFBundleName': '$(PRODUCT_NAME)',
        'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': '1.0', 'CFBundleVersion': '1',
        'UILaunchScreen': {}, 'UISupportedInterfaceOrientations': ['UIInterfaceOrientationPortrait', 'UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight', 'UIInterfaceOrientationPortraitUpsideDown']}
(out / 'Info.plist').write_bytes(plistlib.dumps(info))
for language in ['en', 'zh-Hans']:
    (out / f'{language}.lproj').mkdir(exist_ok=True)
    shutil.copyfile(repo / f'SunSmart/{language}.lproj/Localizable.strings', out / f'{language}.lproj/Localizable.strings')
objects = {}
def obj(isa, **kwargs):
    key = f'{len(objects)+1:024X}'
    objects[key] = {'isa': isa, **kwargs}
    return key

def configs(settings):
    entries = [obj('XCBuildConfiguration', name=name, buildSettings=settings) for name in ['Debug', 'Release']]
    return obj('XCConfigurationList', buildConfigurations=entries, defaultConfigurationIsVisible=0, defaultConfigurationName='Debug')
app_ref = obj('PBXFileReference', lastKnownFileType='sourcecode.swift', path='App.swift', sourceTree='<group>')
test_ref = obj('PBXFileReference', lastKnownFileType='sourcecode.swift', path='RecoveryUITests.swift', sourceTree='<group>')
localized = [obj('PBXFileReference', lastKnownFileType='text.plist.strings', name=language,
                 path=f'{language}.lproj/Localizable.strings', sourceTree='<group>') for language in ['en', 'zh-Hans']]
strings = obj('PBXVariantGroup', name='Localizable.strings', children=localized, sourceTree='<group>')
app_product = obj('PBXFileReference', explicitFileType='wrapper.application', path='RecoveryLayout.app', sourceTree='BUILT_PRODUCTS_DIR')
test_product = obj('PBXFileReference', explicitFileType='wrapper.cfbundle', path='RecoveryUITests.xctest', sourceTree='BUILT_PRODUCTS_DIR')
products = obj('PBXGroup', name='Products', children=[app_product, test_product], sourceTree='<group>')
main = obj('PBXGroup', children=[app_ref, test_ref, strings, products], sourceTree='<group>')
base = {'SDKROOT': 'iphoneos', 'IPHONEOS_DEPLOYMENT_TARGET': '16.4', 'SWIFT_VERSION': '5.0',
        'TARGETED_DEVICE_FAMILY': '1,2', 'CODE_SIGN_STYLE': 'Automatic', 'PRODUCT_NAME': '$(TARGET_NAME)',
        'SWIFT_OPTIMIZATION_LEVEL': '-Onone', 'ENABLE_TESTABILITY': 'YES', 'ALWAYS_SEARCH_USER_PATHS': 'NO'}
app_target = obj('PBXNativeTarget', name='RecoveryLayout', productName='RecoveryLayout', productReference=app_product,
    productType='com.apple.product-type.application', buildRules=[], dependencies=[],
    buildConfigurationList=configs(base | {'PRODUCT_BUNDLE_IDENTIFIER': 'com.sunricher.recovery-layout-test', 'INFOPLIST_FILE': 'Info.plist'}),
    buildPhases=[obj('PBXSourcesBuildPhase', files=[obj('PBXBuildFile', fileRef=app_ref)], buildActionMask=2147483647, runOnlyForDeploymentPostprocessing=0),
                 obj('PBXResourcesBuildPhase', files=[obj('PBXBuildFile', fileRef=strings)], buildActionMask=2147483647, runOnlyForDeploymentPostprocessing=0)])
test_target = obj('PBXNativeTarget', name='RecoveryUITests', productName='RecoveryUITests', productReference=test_product,
    productType='com.apple.product-type.bundle.ui-testing', buildRules=[], dependencies=[],
    buildConfigurationList=configs(base | {'PRODUCT_BUNDLE_IDENTIFIER': 'com.sunricher.recovery-layout-tests', 'GENERATE_INFOPLIST_FILE': 'YES', 'TEST_TARGET_NAME': 'RecoveryLayout'}),
    buildPhases=[obj('PBXSourcesBuildPhase', files=[obj('PBXBuildFile', fileRef=test_ref)], buildActionMask=2147483647, runOnlyForDeploymentPostprocessing=0)])
project = obj('PBXProject', attributes={'LastUpgradeCheck': '1600'}, buildConfigurationList=configs({}),
    compatibilityVersion='Xcode 14.0', developmentRegion='en', knownRegions=['en', 'zh-Hans'],
    mainGroup=main, productRefGroup=products, projectDirPath='', projectRoot='', targets=[app_target, test_target])
proxy = obj('PBXContainerItemProxy', containerPortal=project, proxyType=1, remoteGlobalIDString=app_target, remoteInfo='RecoveryLayout')
objects[test_target]['dependencies'] = [obj('PBXTargetDependency', target=app_target, targetProxy=proxy)]
proj_dir = out / 'RecoveryLayout.xcodeproj'; proj_dir.mkdir(exist_ok=True)
(proj_dir / 'project.pbxproj').write_bytes(plistlib.dumps({'archiveVersion': '1', 'classes': {}, 'objectVersion': '56', 'objects': objects, 'rootObject': project}))
schemes = proj_dir / 'xcshareddata/xcschemes'; schemes.mkdir(parents=True, exist_ok=True)
def ref(target, name, suffix):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{name}.{suffix}" BlueprintName="{name}" ReferencedContainer="container:RecoveryLayout.xcodeproj"/>'
(schemes / 'RecoveryLayout.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
<BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES">{ref(app_target, 'RecoveryLayout', 'app')}</BuildActionEntry>
<BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES">{ref(test_target, 'RecoveryUITests', 'xctest')}</BuildActionEntry>
</BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{ref(test_target, 'RecoveryUITests', 'xctest')}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB"><BuildableProductRunnable runnableDebuggingMode="0">{ref(app_target, 'RecoveryLayout', 'app')}</BuildableProductRunnable></LaunchAction></Scheme>''')
print(proj_dir)
