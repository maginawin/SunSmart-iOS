#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
swiftc -module-cache-path "$test_dir/modules" -parse-as-library \
 "$repo_root/SunSmart/Common/Data/SiteTimeZoneValue.swift" \
 "$repo_root/SunSmart/Common/Data/SiteTimeSetMessageFactory.swift" \
 "$repo_root/SunSmart/Main/Site/Model/SiteTimeZoneStore.swift" \
 "$repo_root/SunSmart/Main/Space/Model/SpaceClockSyncCoordinator.swift" \
 "$repo_root/Tests/Site/SpaceClockSyncSessionTests.swift" -o "$test_dir/clock"
"$test_dir/clock"
