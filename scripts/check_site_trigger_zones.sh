#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
swiftc -parse-as-library \
  "$repo_root/SunSmart/Main/Site/TriggerZone/SiteTriggerZoneData.swift" \
  "$repo_root/Tests/Site/SiteTriggerZoneDataTests.swift" \
  -o "$test_dir/site_trigger_zones"
"$test_dir/site_trigger_zones"
swiftc -D DEBUG -parse-as-library \
  "$repo_root/SunSmart/Main/Site/TriggerZone/SiteTriggerZoneItemModel.swift" \
  "$repo_root/SunSmart/Main/Site/TriggerZone/SiteTriggerZonePreviewFixtures.swift" \
  "$repo_root/Tests/Site/SiteTriggerZoneItemPolicyTests.swift" \
  -o "$test_dir/site_trigger_zone_items"
"$test_dir/site_trigger_zone_items"
swiftc -parse-as-library \
  "$repo_root/SunSmart/Main/Site/TriggerZone/SiteTriggerZoneCandidatePolicy.swift" \
  "$repo_root/SunSmart/Main/Site/TriggerZone/SiteTriggerZoneCandidateReader.swift" \
  "$repo_root/Tests/Site/SiteTriggerZoneCandidateTests.swift" \
  -lsqlite3 -o "$test_dir/site_trigger_zone_candidates"
"$test_dir/site_trigger_zone_candidates"
