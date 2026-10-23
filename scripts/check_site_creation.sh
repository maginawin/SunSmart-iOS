#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
swiftc -parse-as-library \
  "$repo_root/SunSmart/Common/Data/SiteExtensionData.swift" \
  "$repo_root/SunSmart/Common/Data/SiteExtensionState.swift" \
  "$repo_root/SunSmart/Main/Site/TriggerZone/SiteTriggerZoneData.swift" \
  "$repo_root/Tests/Site/SiteCreationMetadataTests.swift" \
  -o "$test_dir/metadata"
"$test_dir/metadata"
swiftc -parse-as-library \
  "$repo_root/SunSmart/Common/Data/SiteExtensionData.swift" \
  "$repo_root/SunSmart/Common/Data/SiteTimeZoneValue.swift" \
  "$repo_root/SunSmart/Main/Site/TriggerZone/SiteTriggerZoneData.swift" \
  "$repo_root/SunSmart/Main/Site/Model/SiteCreationDraft.swift" \
  "$repo_root/SunSmart/Main/Site/Model/SiteTimeZoneCatalog.swift" \
  "$repo_root/Tests/Site/SiteCreationDraftTests.swift" \
  -o "$test_dir/draft"
"$test_dir/draft" "$repo_root/SunSmart/all_utc_timezones.json"
