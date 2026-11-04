#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
common=("$repo_root/SunSmart/Common/Data/SiteTimeZoneValue.swift")
for test in SiteTimeZoneValueTests SiteTimeZoneSnapshotTests; do
  swiftc -module-cache-path "$test_dir/modules" -parse-as-library "${common[@]}" "$repo_root/Tests/Site/$test.swift" -o "$test_dir/$test"
  "$test_dir/$test"
done
swiftc -module-cache-path "$test_dir/modules" -parse-as-library "${common[@]}" "$repo_root/SunSmart/Main/Site/Model/SiteTimeZoneStore.swift" "$repo_root/Tests/Site/SiteTimeZoneStoreTests.swift" -o "$test_dir/store"
"$test_dir/store"
