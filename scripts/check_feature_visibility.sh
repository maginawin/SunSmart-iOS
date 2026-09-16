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
menu = controller[controller.index('    @objc private func moreClick()'):start]
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
done

plutil -lint SunSmart.xcodeproj/project.pbxproj
git diff --check
