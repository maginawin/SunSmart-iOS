#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
test_source="$repo_root/Tests/Site/SiteGatewayOnlineStateContractTests.swift"
site_source="$repo_root/SunSmart/Main/Site/Controller/SiteViewController.swift"
gateway_source="$repo_root/SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift"
temp_dir="$(mktemp -d)"
test_binary="$temp_dir/site_gateway_online_state_contract_tests"

cleanup() {
  rm -rf "$temp_dir"
}
trap cleanup EXIT

swiftc -parse-as-library "$test_source" -o "$test_binary"
"$test_binary" "$site_source" "$gateway_source"

echo "PASS: Site Gateway online-state source ownership checks passed."
