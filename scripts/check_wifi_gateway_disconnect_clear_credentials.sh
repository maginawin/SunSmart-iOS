#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

controller="SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift"
cell="SunSmart/Main/Device/Gateway/View/GatewayNetworkConnectivityCell.swift"

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

rg -n "removeCachedPassword" "$controller" >/dev/null \
  || fail "WiFiGatewayViewController must remove the cached password for the cleared SSID."

if rg -n "Invalid parameters|参数错误|invalid_parameters" SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings "$controller" >/dev/null; then
  fail "Clear credentials parameter errors must reuse the existing failed prompt, not a new parameter-error string."
fi

rg -n "handleNetworkConnectionFinished\\(\\.failure\\)" "$controller" >/dev/null \
  || fail "WiFiGatewayViewController must show the existing failed prompt for clear failures."

echo "PASS: WiFi Gateway Disconnect sends clear credentials and handles waiting/failure contract."
