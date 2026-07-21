#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

controller="SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift"
cell="SunSmart/Main/Device/Gateway/View/GatewayNetworkConnectivityCell.swift"
mutation_reducer="SunSmart/Main/Device/Gateway/Model/WiFiGatewayCredentialMutationReducer.swift"
mutation_test="Tests/Device/WiFiGatewayCredentialMutationReducerTests.swift"

rg -n "case disconnecting" "$cell" >/dev/null \
  || fail "GatewayNetworkConnectivityCell must expose a dedicated disconnecting state."

rg -n "connectState == \\.connecting \\|\\| connectState == \\.disconnecting|\\[\\.connecting, \\.disconnecting\\]" "$cell" >/dev/null \
  || fail "GatewayNetworkConnectivityCell must show loading for both connecting and disconnecting."

rg -n "SunricherVendorSet\\(function: \\.wifiGatewayCredentialsClear\\)" "$controller" >/dev/null \
  || fail "WiFiGatewayViewController disconnect must send the WiFi Gateway credentials clear command."

rg -n "WiFiGatewayCredentialsClearResult" "$controller" >/dev/null \
  || fail "WiFiGatewayViewController must parse the typed clear credentials result."

rg -n "networkConnectState = \\.disconnecting" "$controller" >/dev/null \
  || fail "WiFiGatewayViewController must enter disconnecting state while waiting for clear response."

rg -n "clearLocalNetworkFields\\(" "$controller" >/dev/null \
  || fail "WiFiGatewayViewController must clear local SSID and password after clear completion."

if rg -n "removeCachedPassword" "$controller" >/dev/null; then
  fail "WiFiGatewayViewController must keep the cached password for the cleared SSID."
fi

if rg -n "Invalid parameters|参数错误|invalid_parameters" SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings "$controller" >/dev/null; then
  fail "Clear credentials parameter errors must reuse the existing failed prompt, not a new parameter-error string."
fi

rg -n "handleNetworkConnectionFinished\\(\\.failure\\)" "$controller" >/dev/null \
  || fail "WiFiGatewayViewController must show the existing failed prompt for clear failures."

rg -n "credentialMutationReducer" "$controller" >/dev/null \
  || fail "WiFi credential SET/CLEAR must use the mutation reducer."

rg -n "case \.requestCredentials:" "$controller" >/dev/null \
  || fail "Unconfirmed mutations must request one authoritative credentials read."

recovery_call_count=$(grep -Fc 'requestCredentialMutationRecovery(operationID: operationID)' "$controller")
[ "$recovery_call_count" -eq 1 ] \
  || fail "Credential mutation recovery must have exactly one 0x12 driver call site."

if rg -n "completeNetworkDisconnectClear" "$controller" >/dev/null; then
  fail "Clear must not erase local fields before reducer confirmation."
fi

rg -U -n 'case \.clearTargetReached:[[:space:][:print:]]*clearLocalNetworkFields\(\)' "$controller" >/dev/null \
  || fail "Local fields may only be cleared after clear target confirmation."

swiftc -parse-as-library "$mutation_reducer" "$mutation_test" -o /tmp/WiFiGatewayCredentialMutationReducerTests
/tmp/WiFiGatewayCredentialMutationReducerTests

echo "PASS: WiFi Gateway Disconnect sends clear credentials and handles waiting/failure contract."
