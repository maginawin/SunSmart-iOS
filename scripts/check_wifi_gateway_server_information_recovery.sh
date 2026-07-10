#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

service="SunSmart/Main/Device/Gateway/Model/GatewayServerAuthorizationService.swift"
project="SunSmart.xcodeproj/project.pbxproj"

test -f "$service" || fail "Gateway Server Authorization service is missing"
rg -n "actor GatewayServerAuthorizationService" "$service" >/dev/null \
  || fail "Authorization requests must be coordinated by an actor"
rg -n "case noNetwork|case nodeExportFailed|case requestFailed|case invalidResponse|case persistenceFailed" "$service" >/dev/null \
  || fail "Authorization must expose explicit failure categories"
for field in mqttUsername mqttPassword mqttClientId host port; do
  rg -n "data\[\"$field\"\]" "$service" >/dev/null \
    || fail "Gateway Register parser must require $field"
done
rg -n "func authorize\(" "$service" >/dev/null \
  || fail "Authorization service must expose authorize"
rg -n "gateway\.save\(\)" "$service" >/dev/null \
  || fail "Valid MQTT information must be persisted"
rg -n "GatewayServerAuthorizationService.swift" "$project" | awk 'END { exit(NR >= 6 ? 0 : 1) }' \
  || fail "Authorization service must have one file reference, four build files, and a group reference"
if rg -n 'print\(.*(mqttUsername|mqttPassword|mqttClientId|response)' "$service" >/dev/null; then
  fail "Authorization service must not log credentials or the full response"
fi

add_controller="SunSmart/Main/Site/Controller/SiteDeviceAddViewController.swift"
cloud_manager="SunSmart/Common/Cloud/CloudSynchronizationManager.swift"

rg -n "GatewayServerAuthorizationService\.shared\.authorize" "$add_controller" >/dev/null \
  || fail "Fast Add must use the shared Authorization service"
if rg -n 'mqttUsername|mqttPassword|mqttClientId' "$add_controller" >/dev/null; then
  fail "Fast Add must not keep a duplicate Gateway Register parser"
fi
rg -n "GatewayServerAuthorizationService\.shared\.authorize" "$cloud_manager" >/dev/null \
  || fail "Cloud sync must use the shared Authorization service"
rg -n "policy: \.always" "$cloud_manager" >/dev/null \
  || fail "Cloud sync must still upload/register when a local target exists"
rg -n "gatewayAuthorizationTask\?\.cancel\(\)" "$cloud_manager" >/dev/null \
  || fail "Cloud cancellation must invalidate the Authorization waiter"
rg -n "gateway\.syncCloudError = authorizationError\.networkApiError" "$cloud_manager" >/dev/null \
  || fail "Missing credentials must fail Cloud sync when no local target exists"

cell_model="SunSmart/Main/Space/Model/SyncDevicesCellModel.swift"
sync_controller="SunSmart/Main/Space/Controller/SyncDevicesViewController.swift"
progress_view="SunSmart/Main/Space/View/SyncDevicesProgressView.swift"
en_strings="SunSmart/en.lproj/Localizable.strings"
zh_strings="SunSmart/zh-Hans.lproj/Localizable.strings"

rg -n "case gatewayServerAuthorization\(gateway: GatewayModel\)" "$cell_model" >/dev/null \
  || fail "ActionType must define Server Authorization"
rg -n "case gatewayServerInformation\(gateway: GatewayModel\)" "$cell_model" >/dev/null \
  || fail "Server Information must read GatewayModel dynamically"
rg -n "GatewayServerAuthorizationService\.isValid\(gateway\.mqttServerInfo\)" "$cell_model" >/dev/null \
  || fail "Recovery verification must require a valid local MQTT target"
rg -n "case gatewayServerRecovery\(" "$sync_controller" >/dev/null \
  || fail "SyncType must define focused server recovery"
rg -n "makeGatewayServerRecoverySteps" "$sync_controller" >/dev/null \
  || fail "Repair and Authorize must share a server task builder"
rg -n "completeGatewayServerAuthorizationTaskIfNeeded" "$sync_controller" >/dev/null \
  || fail "Sync worker must execute the HTTP Authorization task"
rg -n "authorizationDependencies" "$sync_controller" >/dev/null \
  || fail "Server Information must depend on Authorization"
rg -n "failureMessage" "$cell_model" "$progress_view" >/dev/null \
  || fail "Authorization errors must be visible in task details"
rg -n '"server_authorization" = "Server Authorization";' "$en_strings" >/dev/null \
  || fail "English Server Authorization localization is missing"
rg -n '"server_authorization" = "服务器授权";' "$zh_strings" >/dev/null \
  || fail "Chinese Server Authorization localization is missing"

gateway_controller="SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift"
wifi_controller="SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift"

rg -n "func performServerAuthorization\\(\\)" "$gateway_controller" >/dev/null \
  || fail "Gateway controller must expose an overridable Authorization hook"
rg -n "func recoverServerInformation\\(\\)" "$gateway_controller" >/dev/null \
  || fail "Gateway controller must expose focused server recovery navigation"
rg -n "refreshServerInformationFromPersistence" "$gateway_controller" >/dev/null \
  || fail "Gateway page must refresh persisted Server Information"
rg -n "override func performServerAuthorization\\(\\)" "$wifi_controller" >/dev/null \
  || fail "WiFi Gateway must override Authorize"
rg -n "recoverServerInformation\\(\\)" "$wifi_controller" >/dev/null \
  || fail "WiFi Authorize must enter the focused Sync chain"
rg -n "prepareForGatewayRecovery" "$wifi_controller" >/dev/null \
  || fail "WiFi Authorize must reuse the acknowledged-request coordinator"
rg -n "self\\.performServerAuthorization\\(\\)" "$gateway_controller" >/dev/null \
  || fail "Server Information header must call the overridable hook"

echo "PASS: WiFi Gateway Server Authorization service contracts"
