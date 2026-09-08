#!/usr/bin/env python3
"""复制生产按钮构造与完整按钮约束，生成不接入业务数据的真机测试 App。"""
from pathlib import Path
import plistlib
import re
import runpy
import shutil
import sys

sys.dont_write_bytecode = True
root = Path(__file__).resolve().parents[1]
out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('/tmp/WarningButtonLayout')
sys.argv = [str(root / 'scripts/prepare_configuration_recovery_ui_tests.py'), str(out)]
runpy.run_path(sys.argv[0], run_name='__main__')


def between(source, start, end):
    begin = source.index(start)
    return source[begin:source.index(end, begin)]


def button_region(name, button, occurrence=0):
    source = next((root / 'SunSmart').rglob(name)).read_text()
    starts = list(re.finditer(r'^        ' + button + r' = (?:UIButton|TrailingImageButton)\(', source, re.M))
    begin = starts[occurrence].start()
    opening = source.index('{', source.index(button + '.snp.makeConstraints', begin))
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[begin:end]


specs = [
    ('SiteDeviceAddViewController.swift', 'scanBtn', 0),
    ('DeviceAddClassicModeController.swift', 'scanBtn', 0),
    ('DeviceAddProfessionalModeController.swift', 'scanBtn', 0),
    ('DeviceAddProfessionalModeController.swift', 'scanBtn', 1),
    ('DeviceRestoreViewController.swift', 'scanBtn', 0),
    ('DeviceAddCandidateDeviceListView.swift', 'scanBtn', 0),
    ('DeviceAddClassicModeController.swift', 'addDeviceTargetBtn', 0),
    ('DeviceAddCandidateDeviceListView.swift', 'addDeviceTargetBtn', 0),
    ('EnergyStaticDataViewController.swift', 'viewTypeBtn', 0),
    ('DeviceAddViewCell.swift', 'identifyBtn', 0),
    ('DeviceForceResetViewCell.swift', 'identifyBtn', 0),
]
methods = []
for index, (name, button, occurrence) in enumerate(specs):
    body = button_region(name, button, occurrence)
    setup = []
    for alias in ['headerView', 'contentView', 'view']:
        if re.search(r'\b' + alias + r'\b', body):
            setup.append(f'let {alias} = container')
    if 'addDeviceToLabel' in body or 'addModeBtn' in body:
        setup.append('''let addDeviceToLabel = UILabel()
        addDeviceToLabel.text = "Target"
        addDeviceToLabel.textColor = .black
        container.addSubview(addDeviceToLabel)
        addDeviceToLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16)); make.centerY.equalToSuperview(); make.width.equalTo(SCRXFrom(55))
        }''')
    if 'addModeBtn' in body:
        setup.append('let addModeBtn = addDeviceToLabel')
    if 'energyReportLabel' in body:
        setup.append('''let energyReportLabel = UILabel()
        container.addSubview(energyReportLabel)
        energyReportLabel.snp.makeConstraints { make in
            make.left.top.equalToSuperview(); make.width.height.equalTo(1)
        }''')
    for anchor in ['scanBtn', 'addBtn', 'resetBtn']:
        if anchor != button and re.search(r'\b' + anchor + r'\b', body):
            width = 'SCRXFrom(72)' if anchor == 'scanBtn' else 'SCRYFrom(30)'
            setup.append(f'''let {anchor} = UIButton()
        container.addSubview({anchor})
        {anchor}.snp.makeConstraints {{ make in
            make.right.equalTo(SCRXFrom(-16)); make.centerY.equalToSuperview()
            make.width.equalTo({width}); make.height.equalTo(SCRYFrom(30))
        }}''')
    if button != 'addDeviceTargetBtn' and 'addDeviceTargetBtn' in body:
        setup.append('let addDeviceTargetBtn = addDeviceToLabelButton(container)')
    if 'targetName' in body:
        setup.append('let targetName = "space".localizedString')
    setup.append(f'let {button}: UIButton')
    declarations = '\n        '.join(setup)
    methods.append(f'''    func mount{index}(_ container: UIView) -> UIButton {{
        {declarations}
{body}
        {button}.isHidden = false
        {button}.accessibilityIdentifier = "button-{index}"
        return {button}
    }}''')

extension = (root / 'SunSmart/Common/Extension/UIButton+Extension.swift').read_text()
support = 'import UIKit\nimport SnapKit\n'
support += between((root / 'SunSmart/Common/Macro/MacroDefinition.swift').read_text(), 'var SCREEN_WIDTH:', '// 检查当前首选语言是否是中文')
support += '''
func RGB(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> UIColor { UIColor(red: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: a) }
let TextBlack_Color = RGB(30,35,41), Border_Color = RGB(236,236,236)
let Bottom_Done_Color = RGB(0,122,255), Bar_Color = RGB(0,122,255), Purple_Color = RGB(102,103,171)
extension String { var localizedString: String { NSLocalizedString(self, comment: "") } }
'''
support += 'extension UIButton {\n' + between(extension, '    convenience init(', '    func setImagePosition(') + '\n}\n'
support += extension[extension.index('// Opt-in layout'):]
template = (root / 'Tests/UI/WarningButtonLayoutApp.swift').read_text()
mounts = '\n'.join(f'        mounts.append(mount{i})' for i in range(len(specs)))
camera = (root / 'Tests/UI/WarningCameraSmokeApp.swift').read_text()
camera += (root / 'SunSmart/Thirdparty/ScanQRCode/LBXScanWrapper.swift').read_text()
(out / 'App.swift').write_text(support + template.replace('// MOUNTS', mounts).replace('// METHODS', '\n'.join(methods)) + camera)
shutil.copyfile(root / 'Tests/UI/WarningButtonUITests.swift', out / 'RecoveryUITests.swift')
info_path = out / 'Info.plist'
info = plistlib.loads(info_path.read_bytes())
info['CFBundleDisplayName'] = 'Warning Layout Test'
info['UISupportedInterfaceOrientations'] = ['UIInterfaceOrientationPortrait']
info['UIRequiresFullScreen'] = True
info['NSCameraUsageDescription'] = 'Verify scanner photo capture on this test device.'
info_path.write_bytes(plistlib.dumps(info))
shutil.copytree(root / 'Pods/SnapKit/Sources', out / 'SnapKit', dirs_exist_ok=True, copy_function=shutil.copyfile)
assets = out / 'Assets.xcassets'
assets.mkdir(exist_ok=True)
(assets / 'Contents.json').write_text('{"info":{"author":"xcode","version":1}}')
names = set(re.findall(r'"([a-z][a-z0-9_]+)"', '\n'.join(methods)))
for name in names:
    matches = list((root / 'SunSmart/Assets.xcassets').rglob(name + '.imageset'))
    if matches:
        shutil.copytree(matches[0], assets / matches[0].name, dirs_exist_ok=True)
project_path = out / 'RecoveryLayout.xcodeproj/project.pbxproj'
project = plistlib.loads(project_path.read_bytes())
objects = project['objects']


def obj(isa, **kwargs):
    key = f'{max(int(x, 16) for x in objects) + 1:024X}'
    objects[key] = dict(isa=isa, **kwargs)
    return key


app_target = next(v for v in objects.values() if v.get('isa') == 'PBXNativeTarget' and v.get('name') == 'RecoveryLayout')
phases = [objects[key] for key in app_target['buildPhases']]
sources = next(v for v in phases if v['isa'] == 'PBXSourcesBuildPhase')
resources = next(v for v in phases if v['isa'] == 'PBXResourcesBuildPhase')
main = objects[objects[project['rootObject']]['mainGroup']]
for source in sorted((out / 'SnapKit').glob('*.swift')):
    ref = obj('PBXFileReference', lastKnownFileType='sourcecode.swift', path=str(source.relative_to(out)), sourceTree='<group>')
    main['children'].append(ref)
    sources['files'].append(obj('PBXBuildFile', fileRef=ref))
# SnapKit sources share the isolated app module, so their import is unnecessary.
app_path = out / 'App.swift'
app_path.write_text(app_path.read_text().replace('import SnapKit\n', ''))
ref = obj('PBXFileReference', lastKnownFileType='folder.assetcatalog', path='Assets.xcassets', sourceTree='<group>')
main['children'].append(ref)
resources['files'].append(obj('PBXBuildFile', fileRef=ref))
for value in objects.values():
    settings = value.get('buildSettings', {})
    bundle = settings.get('PRODUCT_BUNDLE_IDENTIFIER', '')
    if bundle:
        settings['PRODUCT_BUNDLE_IDENTIFIER'] = bundle.replace('recovery-layout', 'warning-layout')
project_path.write_bytes(plistlib.dumps(project))
print(out / 'RecoveryLayout.xcodeproj')
