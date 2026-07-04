#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

gateway_controller="SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift"
wifi_controller="SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift"
wifi_cell="SunSmart/Main/Device/Gateway/View/GatewayNetworkConnectivityCell.swift"
localizable_en="SunSmart/en.lproj/Localizable.strings"
localizable_zh="SunSmart/zh-Hans.lproj/Localizable.strings"

rg -n "case networkConnectivity|network_connectivity|GatewayNetworkConnectivityCell" "$gateway_controller" >/dev/null || fail "GatewayViewController missing network connectivity hook"
rg -n "func reloadGatewayTable\(\)" "$gateway_controller" >/dev/null || fail "GatewayViewController missing full table reload hook"
rg -n "func gatewayOnlineStateDidUpdate\(_ isOnline: Bool\)" "$gateway_controller" >/dev/null || fail "GatewayViewController missing online-state hook"
rg -n "var supportsGatewaySignalRefresh: Bool" "$gateway_controller" >/dev/null || fail "GatewayViewController missing signal refresh capability hook"
rg -n "guard supportsGatewaySignalRefresh else" "$gateway_controller" >/dev/null || fail "Gateway signal refresh must be capability-gated"

rg -n "wifiGatewayCredentials|wifiGatewayConnectionStatus|wifiGatewayCredentialsSet" "$wifi_controller" >/dev/null || fail "WiFiGatewayViewController must use real WiFi Gateway vendor protocol"
rg -n "override var supportsGatewaySignalRefresh: Bool" "$wifi_controller" >/dev/null || fail "WiFi Gateway must disable legacy 4G signal refresh"
rg -n "startNetworkConnectionSimulation|finishNetworkConnectionSimulation|disconnectNetworkSimulation" "$wifi_controller" && fail "WiFiGatewayViewController must not keep simulation methods"
rg -n "WiFiGatewayCredentialsReadResult|WiFiGatewayConnectionStatus|WiFiGatewayCredentialsSetResult" "$wifi_controller" >/dev/null || fail "WiFiGatewayViewController must parse typed WiFi Gateway results"
rg -n "status\.isSuccessful.*connected|connected.*status\.isSuccessful" "$wifi_controller" && fail "WiFi connection success must not use status.isSuccessful"
rg -n "UserDefaults\.standard" "$wifi_controller" >/dev/null || fail "WiFi passwords must be cached in UserDefaults"
rg -n "ssidClearCallback|clearNetworkSSIDLocally|showsSSIDClearButton" "$wifi_controller" "$wifi_cell" >/dev/null || fail "SSID clear behavior missing"
rg -n "isNetworkConnectivityVisible|setNetworkConnectivityVisible" "$wifi_controller" >/dev/null || fail "Network Connectivity section visibility must be state-driven"
rg -n "connectionPollTimeout|networkConnectionStartedAt|pollNetworkConnectionStatus" "$wifi_controller" >/dev/null || fail "Connection polling timeout missing"
rg -n "pendingNetworkResultHUD|isNetworkPageVisible" "$wifi_controller" >/dev/null || fail "Subpage HUD suppression behavior missing"
rg -n "refreshNetworkConnectivity" "$wifi_controller" >/dev/null || fail "Refresh must route through network connectivity refresh logic"
rg -n "refreshConfiguredGatewayConnectionStatus" "$wifi_controller" >/dev/null || fail "Configured gateway refresh must read WiFi connection status"
rg -n "refreshGatewayCredentials" "$wifi_controller" >/dev/null || fail "Unconfigured refresh must re-read gateway credentials before phone SSID"
rg -n "canToggleNetworkPasswordVisibility" "$wifi_controller" >/dev/null || fail "Password visibility must be enabled independently from password editing"

rg -n "ssidClearButton" "$wifi_cell" >/dev/null || fail "SSID clear button missing from cell"
rg -n "selectWiFiButton\.isEnabled = canSelectWiFi && !isConnecting" "$wifi_cell" >/dev/null || fail "Change Wi-Fi should only be disabled while connecting"
rg -n "canTogglePasswordVisibility" "$wifi_cell" >/dev/null || fail "Password visibility button must have independent enable control"
rg -n "passwordVisibilityButton\.isEnabled = canTogglePasswordVisibility && !isConnecting" "$wifi_cell" >/dev/null || fail "Show password should be disabled only while connecting"
rg -n "passwordChangedCallback: \(\(String\) -> ConnectState\)\?" "$wifi_cell" >/dev/null || fail "Controller should compute connect state while typing"
rg -n "nameField_clear|close" "$wifi_cell" >/dev/null || fail "SSID clear button should reuse an existing clear icon"

rg -n '"wifi_gateway_ssid_empty"|"wifi_gateway_password_length_error"|"wifi_gateway_password_character_error"' "$localizable_en" "$localizable_zh" >/dev/null || fail "WiFi Gateway validation localization missing"

echo "PASS: WiFi Gateway network connectivity real protocol static checks"
