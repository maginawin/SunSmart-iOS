#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
test_source="$repo_root/Tests/Site/SiteGatewayOnlineStateContractTests.swift"
policy_source="$repo_root/SunSmart/Common/Data/SiteGatewayAssociationConsistencyPolicy.swift"
policy_test_source="$repo_root/Tests/Site/SiteGatewayAssociationConsistencyPolicyTests.swift"
site_source="$repo_root/SunSmart/Main/Site/Controller/SiteViewController.swift"
gateway_source="$repo_root/SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift"
import_source="$repo_root/SunSmart/Common/Data/ImportData.swift"
project_file="$repo_root/SunSmart.xcodeproj/project.pbxproj"
temp_dir="$(mktemp -d)"
policy_test_binary="$temp_dir/site_gateway_association_consistency_policy_tests"
test_binary="$temp_dir/site_gateway_online_state_contract_tests"

cleanup() {
  rm -rf "$temp_dir"
}
trap cleanup EXIT

swiftc -parse-as-library \
  "$policy_source" \
  "$policy_test_source" \
  -o "$policy_test_binary"
"$policy_test_binary"

swiftc -parse-as-library "$test_source" -o "$test_binary"
"$test_binary" \
  "$site_source" \
  "$gateway_source" \
  "$import_source"

source_phase_count="$(
  rg -c \
    '^[[:space:]]+[A-F0-9]+ /\* SiteGatewayAssociationConsistencyPolicy.swift in Sources \*/,$' \
    "$project_file" || true
)"
source_phase_count="${source_phase_count:-0}"
[ "$source_phase_count" -eq 4 ] || {
  echo "FAIL: consistency policy must belong to all four app targets" >&2
  exit 1
}

echo "PASS: Site Gateway online-state source ownership checks passed."
