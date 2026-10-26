#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
common=("$repo_root/SunSmart/Common/Data/SiteTimeZoneValue.swift" "$repo_root/SunSmart/Main/Site/Model/SitePropsEditPolicy.swift")
swiftc -parse-as-library "${common[@]}" "$repo_root/Tests/Site/SitePropsEditPolicyTests.swift" -o "$test_dir/policy"
"$test_dir/policy"
swiftc -parse-as-library "${common[@]}" "$repo_root/SunSmart/Main/Site/Model/SitePropsAPIClient.swift" \
  "$repo_root/Tests/Site/SitePropsAPIResponseParserTests.swift" -o "$test_dir/parser"
"$test_dir/parser"
python3 - "$repo_root" "$test_dir" <<'PY'
from pathlib import Path
import sys
root, output = map(Path, sys.argv[1:])
source = (root / 'SunSmart/Common/Data/ImportData.swift').read_text()
start = source.index('    func update(siteJsonData:')
source = source[start:source.index('    /// 添加site内用户资源', start)]
def section(start, end):
    return source[source.index(start):source.index(end, source.index(start))]
# Execute production validation/version/save code. Mesh/Space imports are explicit
# boundaries, including a cleanup timestamp bump and a late concurrent response.
body = section('        guard SpaceMembershipCoordinator.accepts', '        let gatewayImportScope')
body += section('        let json = JSON(siteJsonData)', '        // Process extension fields')
body += section('        if lastUpdate > self.lastUpdate || initialize {', '            // 转让site id') + '        }\n'
body += '        duringPreparation()\n        preparedSiteTimestamp = self.lastUpdate\n        duringSuspension()\n        let meshNetwork: Bool? = true\n'
body += section('        guard meshNetwork != nil else', '        GatewayOrphanGuard.endImport')
(output / 'SiteImportHarness.swift').write_text('import Foundation\nextension SiteData {\n'
    'func importFixture(siteJsonData: [String: Any], initialize: Bool = false, '
    'duringPreparation: () -> Void = {}, duringSuspension: () -> Void = {}) -> Bool {\n'
    + body + 'return true\n}\n}\n')
PY
swiftc -parse-as-library "${common[@]}" "$repo_root/SunSmart/Main/Site/Model/SitePropsAPIClient.swift" \
  "$repo_root/SunSmart/Main/Site/Model/SitePropsEditCoordinator.swift" \
  "$repo_root/Pods/SwiftyJSON/Source/SwiftyJSON/SwiftyJSON.swift" "$test_dir/SiteImportHarness.swift" \
  "$repo_root/Tests/Site/SiteStandardPropsIntegrationTests.swift" -o "$test_dir/integration"
"$test_dir/integration"
entry=("${common[@]}"
  "$repo_root/SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncResponseParser.swift"
  "$repo_root/SunSmart/Main/Site/Model/SiteGatewayAccessScope.swift"
  "$repo_root/SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneTarget.swift"
  "$repo_root/SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncPolicy.swift")
swiftc -parse-as-library "${entry[@]}" "$repo_root/Tests/Site/SiteEntryTimeZoneSyncPolicyTests.swift" -o "$test_dir/entry-policy"
"$test_dir/entry-policy"
swiftc -parse-as-library "${entry[@]}" "$repo_root/SunSmart/Main/Site/Model/SiteEntryTimeZoneSyncCoordinator.swift" \
  "$repo_root/Tests/Site/SiteEntryTimeZoneSyncCoordinatorTests.swift" -o "$test_dir/entry-coordinator"
"$test_dir/entry-coordinator"
