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
timing="SunSmart/Main/Device/Gateway/Model/WiFiGatewayV19Timing.swift"
timing_test="Tests/Device/WiFiGatewayV19TimingTests.swift"
polling_reducer="SunSmart/Main/Device/Gateway/Model/WiFiGatewayConnectionPollingReducer.swift"
polling_test="Tests/Device/WiFiGatewayConnectionPollingReducerTests.swift"

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
rg -n "WiFiGatewayConnectionPollingReducer" "$wifi_controller" >/dev/null || fail "Connection polling must use the V1.9 reducer"
rg -n "WiFiGatewayV19Timing\.responseTimeout\(for: subcode\)" "$wifi_controller" >/dev/null || fail "WiFi GET helper must use the exact Subcode deadline"
rg -n "subcode: WiFiGatewayV19Subcode" "$wifi_controller" >/dev/null || fail "WiFi GET helper must require a Subcode"
rg -n "case \.requestFormatError:" "$wifi_controller" >/dev/null || fail "0x0E request format errors must be handled explicitly"
rg -n "repeats: false" "$wifi_controller" >/dev/null || fail "Connection polling must use one-shot scheduling"
if rg -n "private let connectionPollInterval|private let connectionPollTimeout|networkConnectionStartedAt" "$wifi_controller" >/dev/null; then
  fail "Legacy fixed connection polling constants must be removed"
fi
rg -n "pendingNetworkResultHUD|isNetworkPageVisible" "$wifi_controller" >/dev/null || fail "Subpage HUD suppression behavior missing"
rg -n "refreshNetworkConnectivity" "$wifi_controller" >/dev/null || fail "Refresh must route through network connectivity refresh logic"
rg -n "refreshConfiguredGatewayConnectionStatus" "$wifi_controller" >/dev/null || fail "Configured gateway refresh must read WiFi connection status"
rg -n "refreshGatewayCredentials" "$wifi_controller" >/dev/null || fail "Unconfigured refresh must re-read gateway credentials before phone SSID"
rg -n "networkConnectState == \\.connected" "$wifi_controller" >/dev/null || fail "Connected refresh must be state-driven instead of only source-driven"
rg -n "refreshGatewayCredentials\\(usesPhoneSSIDWhenNotConnected: false\\)" "$wifi_controller" >/dev/null || fail "Connected refresh must re-read gateway credentials before connection status without replacing SSID from phone"
rg -n "refreshCurrentSSID\\(showsResultHUD: true\\)" "$wifi_controller" >/dev/null || fail "Disconnected or unconfigured refresh must read the phone's current SSID"
rg -n "isNetworkRefreshInProgress" "$wifi_controller" >/dev/null || fail "Network Connectivity Refresh must have an independent loading state"
rg -n "beginNetworkRefresh\\(\\)" "$wifi_controller" >/dev/null || fail "Refresh must enter loading before starting the command"
rg -n "finishNetworkRefresh\\(\\)" "$wifi_controller" >/dev/null || fail "Refresh must leave loading after command completion"
rg -n "showRefreshSSIDChangedHUD\\(oldSSID:.*newSSID:" "$wifi_controller" >/dev/null || fail "Phone SSID refresh must compare old and new SSID values"
rg -n "network_unchanged|updated_to_the_new_network|phone_not_connected_to_wifi" "$wifi_controller" >/dev/null || fail "Refresh results must use specific localized prompts"
rg -n "showDisconnectFirstTip\\(\\)" "$wifi_controller" >/dev/null || fail "Connected editing and Change Wi-Fi must explain that the user should disconnect first"
rg -n "canToggleNetworkPasswordVisibility" "$wifi_controller" >/dev/null || fail "Password visibility must be enabled independently from password editing"

rg -n "ssidClearButton" "$wifi_cell" >/dev/null || fail "SSID clear button missing from cell"
rg -n "private let ssidTextField = UITextField\\(\\)" "$wifi_cell" >/dev/null || fail "SSID must be editable through a text field"
rg -n "ssidChangedCallback: \\(\\(String\\) -> ConnectState\\)\\?" "$wifi_cell" >/dev/null || fail "SSID editing must report changes back to the controller"
rg -n "lockedEditCallback" "$wifi_cell" >/dev/null || fail "Locked SSID/password editing must surface an explanatory toast"
rg -n "refreshLoadingImageView" "$wifi_cell" >/dev/null || fail "Refresh button must have an independent loading image view"
rg -n "isRefreshing: Bool" "$wifi_cell" >/dev/null || fail "Cell update must accept a dedicated Refresh loading state"
rg -n "refreshLoadingImageView\\.snp\\.makeConstraints" "$wifi_cell" >/dev/null || fail "Refresh loading image must have explicit constraints"
rg -n "make\\.width\\.height\\.equalTo\\(16\\)" "$wifi_cell" >/dev/null || fail "Refresh loading image must use a fixed 16x16 size"
rg -n "refreshButton\\.setTitle\\(isRefreshing \\? nil : \"refresh\"\\.localizedString" "$wifi_cell" >/dev/null || fail "Refresh text must be replaced by loading while refreshing"
rg -n "refreshButton\\.isEnabled = canRefresh && !isOperating && !isRefreshing" "$wifi_cell" >/dev/null || fail "Refresh must ignore taps while loading"
rg -n "selectWiFiButton\.isEnabled = canSelectWiFi && !isOperating" "$wifi_cell" >/dev/null || fail "Change Wi-Fi should be disabled while a network operation is in progress"
rg -n "canTogglePasswordVisibility" "$wifi_cell" >/dev/null || fail "Password visibility button must have independent enable control"
rg -n "passwordVisibilityButton\.isEnabled = canTogglePasswordVisibility && !isOperating" "$wifi_cell" >/dev/null || fail "Show password should be disabled while a network operation is in progress"
rg -n "passwordChangedCallback: \(\(String\) -> ConnectState\)\?" "$wifi_cell" >/dev/null || fail "Controller should compute connect state while typing"
rg -n "nameField_clear|close" "$wifi_cell" >/dev/null || fail "SSID clear button should reuse an existing clear icon"

rg -n '"wifi_gateway_ssid_empty"|"wifi_gateway_password_length_error"|"wifi_gateway_password_character_error"' "$localizable_en" "$localizable_zh" >/dev/null || fail "WiFi Gateway validation localization missing"
rg -n '"wifi_gateway_ssid_length_error"|"wifi_gateway_configuration_unconfirmed"|"wifi_gateway_clear_unconfirmed"' "$localizable_en" "$localizable_zh" >/dev/null || fail "WiFi Gateway V1.9 localization missing"
rg -n '"please_disconnect_first" = "Please disconnect first";' "$localizable_en" >/dev/null || fail "English localization must define Please disconnect first"
rg -n '"please_disconnect_first" = "请先断开连接";' "$localizable_zh" >/dev/null || fail "Chinese localization must define 请先断开连接"
rg -n -F '"network_unchanged" = "Network unchanged.";' "$localizable_en" >/dev/null || fail "English localization must define Network unchanged."
rg -n -F '"network_unchanged" = "网络未变化。";' "$localizable_zh" >/dev/null || fail "Chinese localization must define 网络未变化。"
rg -n -F '"updated_to_the_new_network" = "Updated to the new network.";' "$localizable_en" >/dev/null || fail "English localization must define Updated to the new network."
rg -n -F '"updated_to_the_new_network" = "已更新为新网络。";' "$localizable_zh" >/dev/null || fail "Chinese localization must define 已更新为新网络。"
rg -n -F '"phone_not_connected_to_wifi" = "Phone is not connected to Wi-Fi.";' "$localizable_en" >/dev/null || fail "English localization must define phone Wi-Fi disconnected prompt"
rg -n -F '"phone_not_connected_to_wifi" = "手机未连接 Wi-Fi。";' "$localizable_zh" >/dev/null || fail "Chinese localization must define phone Wi-Fi disconnected prompt"

swiftc -parse-as-library "$timing" "$timing_test" -o /tmp/WiFiGatewayV19TimingTests
/tmp/WiFiGatewayV19TimingTests
swiftc -parse-as-library "$timing" "$polling_reducer" "$polling_test" -o /tmp/WiFiGatewayConnectionPollingReducerTests
/tmp/WiFiGatewayConnectionPollingReducerTests

echo "PASS: WiFi Gateway network connectivity real protocol static checks"
