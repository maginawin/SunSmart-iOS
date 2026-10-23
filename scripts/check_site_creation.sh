#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
swiftc -module-cache-path "$test_dir/module-cache" -parse-as-library \
  "$repo_root/SunSmart/Common/Data/SiteExtensionData.swift" \
  "$repo_root/SunSmart/Common/Data/SiteExtensionState.swift" \
  "$repo_root/SunSmart/Main/Site/TriggerZone/SiteTriggerZoneData.swift" \
  "$repo_root/Tests/Site/SiteCreationMetadataTests.swift" \
  -o "$test_dir/metadata"
"$test_dir/metadata"
swiftc -module-cache-path "$test_dir/module-cache" -parse-as-library \
  "$repo_root/SunSmart/Common/Data/SiteExtensionData.swift" \
  "$repo_root/SunSmart/Common/Data/SiteTimeZoneValue.swift" \
  "$repo_root/SunSmart/Main/Site/TriggerZone/SiteTriggerZoneData.swift" \
  "$repo_root/SunSmart/Main/Site/Model/SiteCreationDraft.swift" \
  "$repo_root/SunSmart/Main/Site/Model/CityCatalog.swift" \
  "$repo_root/SunSmart/Main/Site/Model/SiteLocationSearchState.swift" \
  "$repo_root/SunSmart/Main/Site/Model/CountryRegionCatalog.swift" \
  "$repo_root/SunSmart/Main/Site/Model/SiteTimeZoneCatalog.swift" \
  "$repo_root/Tests/Site/SiteCreationDraftTests.swift" \
  -o "$test_dir/draft"
"$test_dir/draft" "$repo_root/SunSmart/all_utc_timezones.json"
swiftc -module-cache-path "$test_dir/module-cache" -parse-as-library \
  "$repo_root/SunSmart/Common/Data/SiteExtensionData.swift" \
  "$repo_root/SunSmart/Common/Data/SiteTimeZoneValue.swift" \
  "$repo_root/SunSmart/Main/Site/TriggerZone/SiteTriggerZoneData.swift" \
  "$repo_root/SunSmart/Main/Site/Model/SiteCreationDraft.swift" \
  "$repo_root/SunSmart/Main/Site/Model/CityCatalog.swift" \
  "$repo_root/SunSmart/Main/Site/Model/SiteLocationSearchState.swift" \
  "$repo_root/SunSmart/Main/Site/Model/CountryRegionCatalog.swift" \
  "$repo_root/Tests/Site/CountryRegionCatalogTests.swift" \
  -o "$test_dir/country"
"$test_dir/country" "$repo_root"
swiftc -module-cache-path "$test_dir/module-cache" -parse-as-library \
  "$repo_root/SunSmart/Common/Data/SiteTimeZoneValue.swift" \
  "$repo_root/SunSmart/Main/Site/Model/SiteTimeZoneCatalog.swift" \
  "$repo_root/Tests/Site/SiteTimeZoneCatalogTests.swift" \
  -o "$test_dir/timezones"
"$test_dir/timezones" "$repo_root/SunSmart/all_utc_timezones.json"
swiftc -module-cache-path "$test_dir/module-cache" -parse-as-library \
  "$repo_root/SunSmart/Common/Data/SiteExtensionData.swift" \
  "$repo_root/SunSmart/Common/Data/SiteTimeZoneValue.swift" \
  "$repo_root/SunSmart/Main/Site/TriggerZone/SiteTriggerZoneData.swift" \
  "$repo_root/SunSmart/Main/Site/Model/SiteCreationDraft.swift" \
  "$repo_root/SunSmart/Main/Site/Model/CountryRegionCatalog.swift" \
  "$repo_root/SunSmart/Main/Site/Model/SiteTimeZoneCatalog.swift" \
  "$repo_root/SunSmart/Main/Site/Model/SiteLocationSearchState.swift" \
  "$repo_root/SunSmart/Main/Site/Model/CityCatalog.swift" \
  "$repo_root/Tests/Site/CityCatalogTests.swift" \
  -o "$test_dir/cities"
"$test_dir/cities" "$repo_root"
