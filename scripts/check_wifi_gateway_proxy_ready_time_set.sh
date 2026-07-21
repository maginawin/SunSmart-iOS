#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

gateway_controller="SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift"
wifi_controller="SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift"
time_sync_coordinator="SunSmart/Main/Device/Gateway/Model/WiFiGatewayTimeSyncCoordinator.swift"
project_file="SunSmart.xcodeproj/project.pbxproj"

rg -n "addGlobalProxyReadyObserver|currentProxyReadyContext" "$gateway_controller" >/dev/null \
  || fail "GatewayViewController must subscribe to Proxy Ready and handle late subscription."
rg -n "func gatewayProxyDidBecomeReady\\(_ context: ProxyReadyContext\\)" "$gateway_controller" >/dev/null \
  || fail "GatewayViewController must expose the Proxy Ready subclass hook."
rg -n "removeGlobalProxyReadyObserver" "$gateway_controller" >/dev/null \
  || fail "GatewayViewController must remove its Proxy Ready observer."

rg -n "override func gatewayProxyDidBecomeReady\\(_ context: ProxyReadyContext\\)" "$wifi_controller" >/dev/null \
  || fail "WiFiGatewayViewController must start time sync from Proxy Ready."
rg -n "WiFiGatewayTimeSyncCoordinator\\.shared\\.synchronize" "$wifi_controller" >/dev/null \
  || fail "WiFiGatewayViewController must use the shared per-session time sync coordinator."
rg -n "automaticLoadGate\\.markReady|drainAutomaticLoadIfPossible" "$wifi_controller" >/dev/null \
  || fail "Automatic WiFi configuration must wait behind the time sync barrier."
rg -n "requestAutomaticLoad\\(forceReload: false\\)|requestAutomaticLoad\\(forceReload: true\\)" "$wifi_controller" >/dev/null \
  || fail "Automatic credential loading and RSSI startup must route through the barrier."

rg -n "TimeZone\\.current|Node\\.setLocalTimeMessage\\(\\)" "$time_sync_coordinator" >/dev/null \
  || fail "Time Set must capture the current phone time zone and Date-Time at send time."
rg -n "response is TimeStatus" "$time_sync_coordinator" >/dev/null \
  || fail "Time Set must use acknowledged Time Status validation."
rg -n "WiFiGatewayTimeSyncSessionGate|sessionID" "$time_sync_coordinator" >/dev/null \
  || fail "Time Set must be deduplicated per Proxy/GATT session."
rg -n "WiFiGatewayAutomaticLoadGate|takeIfReady" "$time_sync_coordinator" >/dev/null \
  || fail "Automatic WiFi configuration must have a session-aware barrier."

if rg -n "TimeRole(Get|Set)|timeRole" "$wifi_controller" "$time_sync_coordinator" >/dev/null; then
  fail "WiFi Gateway time sync must not configure or read Time Role."
fi

source_membership_count="$(rg -c "WiFiGatewayTimeSyncCoordinator\\.swift in Sources \\*/," "$project_file")"
[[ "$source_membership_count" == "4" ]] \
  || fail "WiFiGatewayTimeSyncCoordinator.swift must belong to all four app target source phases."

echo "PASS: WiFi Gateway Proxy Ready Time Set static checks"
