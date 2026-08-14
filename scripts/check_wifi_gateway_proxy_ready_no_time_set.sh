#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

wifi_controller="SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift"
automatic_gate="SunSmart/Main/Device/Gateway/Model/WiFiGatewayAutomaticLoadGate.swift"
project_file="SunSmart.xcodeproj/project.pbxproj"

rg -n "override func gatewayProxyDidBecomeReady\(_ context: ProxyReadyContext\)" "$wifi_controller" >/dev/null \
  || fail "WiFi Gateway must still react to Proxy Ready."
rg -n "automaticLoadGate\.markReady\(sessionID: context\.sessionID\)|drainAutomaticLoadIfPossible\(\)" "$wifi_controller" >/dev/null \
  || fail "Proxy Ready must directly open and drain the automatic-load gate."

if rg -n "WiFiGatewayTimeSyncCoordinator|activeTimeSyncContext" "$wifi_controller" >/dev/null; then
  fail "WiFi Gateway page must not retain automatic time synchronization state."
fi
if rg -n "TimeSet|TimeStatus|TimeZone\.current" "$automatic_gate" >/dev/null; then
  fail "Automatic-load gate must remain independent from Gateway time writes."
fi

[[ ! -e SunSmart/Main/Device/Gateway/Model/WiFiGatewayTimeSyncCoordinator.swift ]] \
  || fail "Old WiFi Gateway time coordinator must be removed."
[[ ! -e Tests/Device/WiFiGatewayTimeSyncCoordinatorTests.swift ]] \
  || fail "Old WiFi Gateway time coordinator tests must be removed."
[[ ! -e scripts/check_wifi_gateway_proxy_ready_time_set.sh ]] \
  || fail "Old Proxy Ready TimeSet contract must be removed."

source_membership_count="$(rg -c "WiFiGatewayAutomaticLoadGate\.swift in Sources \*/," "$project_file" || true)"
[[ "$source_membership_count" == "4" ]] \
  || fail "WiFiGatewayAutomaticLoadGate.swift must belong to all four app targets."

printf 'PASS: WiFi Gateway Proxy Ready no longer sends TimeSet.\n'
