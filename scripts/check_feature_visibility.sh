#!/usr/bin/env bash
set -euo pipefail

app_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$app_root"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/feature-visibility.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT

python3 - "$test_dir" <<'PY'
from pathlib import Path
import json
import subprocess
import sys

source = Path('SunSmart/Common/Data/SiteData.swift').read_text()
permission = source[source.index('enum Permission: Int {'):source.index('/// Mesh网络操作权限')]
(Path(sys.argv[1]) / 'Permission.swift').write_text(permission)
controller = Path('SunSmart/Main/Site/Controller/SiteViewController.swift').read_text()
start = controller.index('    private func makeSiteTriggerZoneMenuItem(')
end = controller.index('    /// 编辑场所', start)
method = controller[start:end]
fixture = '''import Foundation
final class SiteMenuHarness {
    let site: SiteData
    var navigationController: NavigationSpy? = NavigationSpy()
    init(site: SiteData) { self.site = site }
    func item(_ visibility: FeatureVisibility) -> MenuPopView.MenuItem? {
        makeSiteTriggerZoneMenuItem(visibility: visibility)
    }
'''
(Path(sys.argv[1]) / 'SiteMenuHarness.swift').write_text(fixture + method + '\n}\n')
space_page = Path('SunSmart/Main/Space/Controller/SpaceViewController.swift').read_text()
exporter = Path('SunSmart/Common/Cloud/DebugCloudJSONExporter.swift').read_text()
# Compile actual menu blocks and share entry guards, substituting only the
# configuration instance and the expensive UIKit/file work after admission.
export_harness = '''import Foundation
final class ExportJSONMenuHarness: UIViewController {
    let site = SiteData(), space = SpaceData()
    let visibility: FeatureVisibility
    let debugJSONExporter: DebugCloudJSONExporter
    init(visibility: FeatureVisibility) {
        self.visibility = visibility
        debugJSONExporter = DebugCloudJSONExporter(visibility: visibility)
        super.init()
    }
'''
for text, anchor, signature in [
    (controller, '    @objc private func moreClick()', 'siteMenu()'),
    (controller, '    private func spaceMenu(', 'cardMenu(space: SpaceData)'),
    (space_page, '    @objc private func moreClick()', 'spaceMenu()')
]:
    start = text.index('        #if DEBUG\n        if FeatureVisibility.shared.isVisible(.siteExportJson,', text.index(anchor))
    end = text.index('        #endif', start) + len('        #endif')
    block = text[start:end].replace('FeatureVisibility.shared', 'visibility')
    export_harness += f'    func {signature} -> [MenuPopView.MenuItem] {{\n        var items: [MenuPopView.MenuItem] = []\n'
    export_harness += block + '\n        return items\n    }\n'
export_harness += '''}
final class DebugCloudJSONExporter {
    let visibility: FeatureVisibility
    var isExporting = false
    var exports = 0
    var lastSpace: SpaceData?
    init(visibility: FeatureVisibility) { self.visibility = visibility }
'''
start = exporter.index('    static func canExport(')
end = exporter.index('    /// Matches', start)
export_harness += exporter[start:end]
start = exporter.index('    func share(')
end = exporter.index('        isExporting = true', start)
export_harness += exporter[start:end].replace('FeatureVisibility.shared', 'visibility')
export_harness += '        exports += 1\n        lastSpace = space\n    }\n}\n'
(Path(sys.argv[1]) / 'ExportJSONMenuHarness.swift').write_text(export_harness)
menu = controller[controller.index('    @objc private func moreClick()'):controller.index('    private func makeSiteTriggerZoneMenuItem(')]
assert 'if let item = makeSiteTriggerZoneMenuItem()' in menu
assert 'SiteTriggerZoneViewController(' not in menu, 'Site menu bypasses shared entry guard'
space_controller = Path('SunSmart/Main/Space/Controller/SpaceMoreViewController.swift').read_text()
assert 'FeatureVisibility' not in space_controller, 'Site feature must not gate the Space menu'
project = json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', 'SunSmart.xcodeproj/project.pbxproj']))
objects = project['objects']
targets = [v for v in objects.values() if v.get('isa') == 'PBXNativeTarget']
expected = {'SunSmart', 'Archipelago', 'SLG Sync Plus', 'SylSmart', 'Lumineux'}
assert {v['name'] for v in targets} == expected
for target in targets:
    for phase_kind, path in [('PBXSourcesBuildPhase', 'FeatureVisibility.swift'), ('PBXResourcesBuildPhase', 'debug_features.json')]:
        refs = [objects[objects[file]['fileRef']].get('path')
                for phase in target['buildPhases'] if objects[phase]['isa'] == phase_kind
                for file in objects[phase]['files']]
        assert refs.count(path) == 1, (target['name'], path, refs.count(path))
print('PASS: all five targets include one visibility source and one configuration resource')
PY

for mode in debug release; do
    flags=(-Onone)
    if [[ "$mode" == debug ]]; then flags+=(-D DEBUG); fi
    swiftc -parse-as-library "${flags[@]}" \
        "$test_dir/Permission.swift" \
        SunSmart/Common/Config/FeatureVisibility.swift \
        Tests/Config/FeatureVisibilityTests.swift \
        -o "$test_dir/FeatureVisibilityTests-$mode"
    "$test_dir/FeatureVisibilityTests-$mode" SunSmart/debug_features.json
    swiftc -parse-as-library "${flags[@]}" \
        "$test_dir/Permission.swift" \
        SunSmart/Common/Config/FeatureVisibility.swift \
        "$test_dir/SiteMenuHarness.swift" \
        Tests/Config/SiteTriggerZoneMenuTests.swift \
        -o "$test_dir/SiteTriggerZoneMenuTests-$mode"
    "$test_dir/SiteTriggerZoneMenuTests-$mode"
    swiftc -parse-as-library "${flags[@]}" \
        "$test_dir/Permission.swift" \
        SunSmart/Common/Config/FeatureVisibility.swift \
        "$test_dir/ExportJSONMenuHarness.swift" \
        Tests/Config/ExportJSONMenuTests.swift \
        -o "$test_dir/ExportJSONMenuTests-$mode"
    "$test_dir/ExportJSONMenuTests-$mode" SunSmart/debug_features.json
done

plutil -lint SunSmart.xcodeproj/project.pbxproj
git diff --check
