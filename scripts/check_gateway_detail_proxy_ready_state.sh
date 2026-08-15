#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

model="SunSmart/Main/Device/Gateway/Model/GatewayDetailProxyConnectionState.swift"
test_file="Tests/Device/GatewayDetailProxyConnectionStateTests.swift"
gateway_controller="SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift"
wifi_controller="SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift"
header_view="SunSmart/Main/Device/Gateway/View/GatewayInformationHeaderView.swift"
project_file="SunSmart.xcodeproj/project.pbxproj"
test_binary="/tmp/GatewayDetailProxyConnectionStateTests"

if rg -n '^import (UIKit|NordicSigMeshSDK)$' "$model" >/dev/null; then
  fail "Gateway detail Proxy state model must depend on Foundation only"
fi

test_count="$(rg -c 'private static func test' "$test_file")"
[[ "$test_count" -eq 12 ]] || fail "Gateway detail Proxy state tests must keep 12 behavior cases"

swiftc -parse-as-library "$model" "$test_file" -o "$test_binary"
"$test_binary"

rg -n 'func updateData\(gateway: Gateway, isProxyReady: Bool\)' "$header_view" >/dev/null \
  || fail "Gateway header must receive explicit target Proxy Ready state"
if rg -n 'node\.state' "$header_view" >/dev/null; then
  fail "Gateway header must not infer detail status from Node.state"
fi

rg -n 'GatewayDetailProxyConnectionStateMachine' "$gateway_controller" >/dev/null \
  || fail "GatewayViewController must own the target Proxy state machine"
rg -n 'var isGatewayProxyReady: Bool' "$gateway_controller" >/dev/null \
  || fail "GatewayViewController must expose target Proxy readiness to subclasses"
rg -n 'addGlobalProxyReadyObserver' "$gateway_controller" >/dev/null \
  || fail "GatewayViewController must observe Proxy Ready sessions"
rg -n 'removeGlobalProxyReadyObserver' "$gateway_controller" >/dev/null \
  || fail "GatewayViewController must remove the Proxy Ready observer"
rg -n 'addGlobalConnectionObserver' "$gateway_controller" >/dev/null \
  || fail "GatewayViewController must observe Mesh disconnects"
rg -n 'removeGlobalConnectionObserver' "$gateway_controller" >/dev/null \
  || fail "GatewayViewController must remove the Mesh connection observer"
rg -n 'currentProxyReadyContext' "$gateway_controller" >/dev/null \
  || fail "GatewayViewController must reconcile an existing Ready snapshot"
rg -n 'context\.nodeAddress == node\.primaryUnicastAddress' "$gateway_controller" >/dev/null \
  || fail "GatewayViewController must match Proxy Ready to the target Gateway"
rg -n 'readyTimedOut\(attemptID:' "$gateway_controller" >/dev/null \
  || fail "GatewayViewController must isolate Proxy Ready timeout by attempt"
rg -n 'withTimeInterval: 20' "$gateway_controller" >/dev/null \
  || fail "GatewayViewController must wait 20 seconds for Proxy Ready after GATT success"

if rg -n '^[[:space:]]*[^/].*onlineState|gatewayOnlineStateDidUpdate' "$gateway_controller" >/dev/null; then
  fail "GatewayViewController must not keep the old Node-driven online state"
fi
if rg -n '^[[:space:]]*[^/].*node\.state' "$gateway_controller" >/dev/null; then
  fail "GatewayViewController runtime gates must use target Proxy Ready instead of Node.state"
fi

rg -n 'override func gatewayProxyReadyStateDidUpdate\(_ isReady: Bool\)' "$wifi_controller" >/dev/null \
  || fail "WiFi Gateway must consume shared target Proxy state"
rg -n 'automaticLoadGate\.markReady\(sessionID: context\.sessionID\)' "$wifi_controller" >/dev/null \
  || fail "WiFi automatic load must remain scoped to the Ready session"
rg -n 'WiFiGatewayProxySessionTracker' "$wifi_controller" >/dev/null \
  || fail "WiFi Gateway must track Ready session replacement"
rg -n 'proxySessionTracker\.invalidate\(\)' "$wifi_controller" >/dev/null \
  || fail "WiFi Gateway must invalidate the previous Ready session"
rg -n 'resetWiFiSessionForUnavailableProxy\(\)' "$wifi_controller" >/dev/null \
  || fail "WiFi Gateway must centralize unavailable Proxy cleanup"
if rg -n 'node\.state' "$wifi_controller" >/dev/null; then
  fail "WiFi Gateway Vendor operations must not use Node.state as a Proxy gate"
fi

build_file_count="$(rg -c 'GatewayDetailProxyConnectionState\.swift in Sources' "$project_file" || true)"
[[ "$build_file_count" -eq 8 ]] \
  || fail "Project must contain four Gateway detail Proxy build-file declarations and four Sources memberships"
file_reference_count="$(rg -c 'path = GatewayDetailProxyConnectionState\.swift;' "$project_file" || true)"
[[ "$file_reference_count" -eq 1 ]] \
  || fail "Project must contain exactly one Gateway detail Proxy file reference"

echo "PASS: Gateway detail Proxy Ready state checks completed."
