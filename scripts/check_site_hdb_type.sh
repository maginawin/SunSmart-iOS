#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
swiftc -parse-as-library \
  "$repo_root/SunSmart/Common/Data/SiteExtensionData.swift" \
  "$repo_root/SunSmart/Common/Data/SiteExtensionState.swift" \
  "$repo_root/SunSmart/Main/Site/TriggerZone/SiteTriggerZoneData.swift" \
  "$repo_root/Tests/Site/SiteHDBTypeTests.swift" \
  -o "$test_dir/site_hdb_type"
"$test_dir/site_hdb_type"
python3 - "$repo_root" "$test_dir" <<'PY'
from pathlib import Path
import sys
root, output = map(Path, sys.argv[1:])
controller = (root / 'SunSmart/Main/Site/Controller/SitesViewController.swift').read_text()
start = controller.index('    private func showCreatedSite(')
end = controller.index('    /// 编辑场所', start)
method = controller[start:end]
harness = '''final class SiteCreationHarness {
    var allSites: [SiteData] = []
    var navigationController: NavigationSpy? = NavigationSpy()
    let allSitesCollectionView = CollectionSpy()
    func setupSectionsData() {}
    func updateEmptyView() {}
    func complete(_ site: SiteData) { showCreatedSite(site) }
'''
(output / 'SiteCreationHarness.swift').write_text(harness + method + '\n}\n')
PY
swiftc -parse-as-library "$test_dir/SiteCreationHarness.swift" \
  "$repo_root/Tests/Site/SiteCreationPresentationTests.swift" -o "$test_dir/site_creation"
"$test_dir/site_creation"
