#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

header_view="SunSmart/Main/Device/Gateway/View/GatewayInformationHeaderView.swift"
wifi_controller="SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift"
en_strings="SunSmart/en.lproj/Localizable.strings"
zh_strings="SunSmart/zh-Hans.lproj/Localizable.strings"
assets_dir="SunSmart/Assets.xcassets"

rg -n "final class GatewayHeaderStatusItemView" "$header_view" >/dev/null \
  || fail "Header must keep using the reusable status item view."

rg -n "func update\\(iconName: String, title: String\\?, status: String, iconSize: CGFloat\\)" "$header_view" >/dev/null \
  || fail "GatewayHeaderStatusItemView update API must accept a style-specific icon size."

rg -n "make.width.height.equalTo\\(iconSize\\)" "$header_view" >/dev/null \
  || fail "GatewayHeaderStatusItemView image size must use the iconSize passed by callers."

rg -n "iconSize: 30" "$header_view" >/dev/null \
  || fail "Wi-Fi status icon size must be 30."

rg -n "private var wifiStatusView: GatewayHeaderStatusItemView" "$header_view" >/dev/null \
  || fail "Header must add a reusable right-side Wi-Fi status view."

rg -n "private var signalContentView: UIView!" "$header_view" >/dev/null \
  || fail "Header must keep the legacy 4G signal view for non-WiFi gateways."

rg -n "func setWiFiStatusVisible\\(_ visible: Bool\\)" "$header_view" >/dev/null \
  || fail "Header must expose a Wi-Fi status visibility switch."

rg -n "func updateWiFiStatus\\(iconName: String, status: String\\)" "$header_view" >/dev/null \
  || fail "Header must expose a Wi-Fi status update method."

rg -n 'title: "wifi_status_title"\.localizedString' "$header_view" >/dev/null \
  || fail "Wi-Fi status title must use localized wifi_status_title."

rg -n "headerView.setWiFiStatusVisible\\(true\\)" "$wifi_controller" >/dev/null \
  || fail "WiFiGatewayViewController must enable the right-side Wi-Fi status view."

rg -n "wifiRSSIStatusTimer" "$wifi_controller" >/dev/null \
  || fail "WiFiGatewayViewController must own a Wi-Fi RSSI status timer."

rg -n "WiFiGatewayV19Timing\.rssiPollDelay" "$wifi_controller" >/dev/null \
  || fail "The next Wi-Fi RSSI query must use the V1.9 5-second delay."

rg -n "scheduleNextWiFiRSSIStatusRefresh\(\)" "$wifi_controller" >/dev/null \
  || fail "Wi-Fi RSSI polling must use completion-driven scheduling."

rg -U -n "wifiRSSIStatusTimer = LCWeakTimer\.scheduledTimer\([[:space:][:print:]]*timeInterval: WiFiGatewayV19Timing\.rssiPollDelay,[[:space:][:print:]]*repeats: false" "$wifi_controller" >/dev/null \
  || fail "Wi-Fi RSSI polling must use a one-shot V1.9 5-second timer."

rg -n "subcode: \.rssiStatus" "$wifi_controller" >/dev/null \
  || fail "Wi-Fi RSSI GET must use the V1.9 4-second Subcode deadline."

if rg -n "wifiRSSIStatusPollInterval" "$wifi_controller" >/dev/null; then
  fail "The old fixed RSSI polling interval must be removed."
fi

rg -n "startWiFiRSSIStatusRefresh\\(\\)" "$wifi_controller" >/dev/null \
  || fail "WiFiGatewayViewController must start Wi-Fi RSSI status refresh when connected."

rg -n "stopWiFiRSSIStatusRefresh\\(\\)" "$wifi_controller" >/dev/null \
  || fail "WiFiGatewayViewController must stop Wi-Fi RSSI status refresh when disconnected."

rg -n "\\.wifiGatewayRSSIStatus," "$wifi_controller" >/dev/null \
  || fail "WiFiGatewayViewController must query Wi-Fi RSSI status via vendor protocol."

rg -n "WiFiGatewayRSSIStatus" "$wifi_controller" >/dev/null \
  || fail "WiFiGatewayViewController must parse typed Wi-Fi RSSI status."

rg -n "switch status\.rssiResult" "$wifi_controller" >/dev/null \
  || fail "Wi-Fi RSSI result must be mapped independently."

rg -n "switch status\.networkStatus" "$wifi_controller" >/dev/null \
  || fail "Internet status must be mapped independently from RSSI."

rg -n "case \.normal:" "$wifi_controller" >/dev/null \
  || fail "NORMAL Internet status must keep the RSSI grade."

if rg -n "notReported|wifiRSSIStatusPollDelay|wifiRSSIStatusRequestTimeout" "$wifi_controller" >/dev/null; then
  fail "Legacy RSSI compatibility and local timing constants must be removed."
fi

rg -n 'localizedStatusKey: "wifi_status_no_internet"' "$wifi_controller" >/dev/null \
  || fail "UNAVAILABLE must display the localized No Internet status."

rg -n 'localizedStatusKey: "wifi_status_unknown"' "$wifi_controller" >/dev/null \
  || fail "UNKNOWN and reserved network states must display the localized Unknown status."

rg -n "wifi_excellent|wifi_good|wifi_poor|wifi_bad|wifi_no_signal|wifi_not_connected" "$wifi_controller" >/dev/null \
  || fail "Wi-Fi status image mapping must include all required assets."

rg -n "static let notConfigured = WiFiHeaderStatus\\(iconName: \"wifi_not_connected\", localizedStatusKey: \"not_configured\"\\)" "$wifi_controller" >/dev/null \
  || fail "Wi-Fi status mapping must include Not Configured using the existing wifi_not_connected asset and not_configured localization."

rg -n "case \\.notConfigured:[[:space:]]*$" "$wifi_controller" >/dev/null \
  || fail "WiFiGatewayViewController must explicitly handle notConfigured credential reads."

rg -n "updateWiFiHeaderStatus\\(\\.notConfigured\\)" "$wifi_controller" >/dev/null \
  || fail "WiFiGatewayViewController must update the header to Not Configured when credentials are not configured or cleared."

rg -n "dbm > -60" "$wifi_controller" >/dev/null \
  || fail "Excellent RSSI threshold must be > -60 dBm."

rg -n "dbm <= -60 && dbm > -69" "$wifi_controller" >/dev/null \
  || fail "Good RSSI threshold must be <= -60 and > -69 dBm."

rg -n "dbm <= -69 && dbm > -80" "$wifi_controller" >/dev/null \
  || fail "Poor RSSI threshold must be <= -69 and > -80 dBm."

rg -n "dbm <= -80" "$wifi_controller" >/dev/null \
  || fail "Bad RSSI threshold must be <= -80 dBm."

rg -n "wifi_status_excellent|wifi_status_good|wifi_status_poor|wifi_status_bad|wifi_status_no_signal|wifi_status_not_connected" "$wifi_controller" >/dev/null \
  || fail "Wi-Fi status labels must use localized keys."

rg -n '"wifi_status_title" = "Wi-Fi";' "$en_strings" >/dev/null \
  || fail "English localization must define wifi_status_title."

rg -n '"wifi_status_title" = "Wi-Fi";' "$zh_strings" >/dev/null \
  || fail "Chinese localization must define wifi_status_title."

rg -n '"wifi_status_not_connected" = "Not Connected";' "$en_strings" >/dev/null \
  || fail "English localization must define Not Connected."

rg -n '"wifi_status_not_connected" = "未连接";' "$zh_strings" >/dev/null \
  || fail "Chinese localization must define 未连接."

rg -n '"wifi_status_no_internet" = "No Internet";' "$en_strings" >/dev/null \
  || fail "English localization must define No Internet."

rg -n '"wifi_status_no_internet" = "无互联网连接";' "$zh_strings" >/dev/null \
  || fail "Chinese localization must define 无互联网连接."

rg -n '"wifi_status_unknown" = "Unknown";' "$en_strings" >/dev/null \
  || fail "English localization must define Unknown."

rg -n '"wifi_status_unknown" = "未知";' "$zh_strings" >/dev/null \
  || fail "Chinese localization must define 未知."

rg -n '"not_configured" = "Not Configured";' "$en_strings" >/dev/null \
  || fail "English localization must define Not Configured."

rg -n '"not_configured" = "未配置";' "$zh_strings" >/dev/null \
  || fail "Chinese localization must define 未配置."

for asset in wifi_excellent wifi_good wifi_poor wifi_bad wifi_no_signal wifi_not_connected; do
  test -d "$assets_dir/$asset.imageset" || fail "Missing asset: $asset.imageset"
done

echo "PASS: WiFi Gateway header Wi-Fi status view and RSSI refresh checks passed."
