#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/ble-firmware-scan.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT

run_case() {
    local name="$1"
    shift
    swiftc -parse-as-library "$@" "$repo_root/Tests/Firmware/$name.swift" -o "$test_dir/$name"
    "$test_dir/$name"
}

policy="$repo_root/SunSmart/Main/Firmware/Model/FirmwareVersionUpdatePolicy.swift"
run_case FirmwareVersionUpdatePolicyTests "$policy"
run_case GatewayFirmwareScanDiagnosticPolicyTests "$policy" "$repo_root/SunSmart/Main/Firmware/Model/GatewayFirmwareScanDiagnosticPolicy.swift"
run_case GatewayFirmwareScanNetworkKeyScopePolicyTests "$repo_root/SunSmart/Main/Firmware/Model/GatewayFirmwareScanNetworkKeyScopePolicy.swift"
run_case BleFirmwareScanSessionTests "$repo_root/SunSmart/Main/Firmware/Model/BleFirmwareScanSession.swift"
