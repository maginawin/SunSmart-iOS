#!/usr/bin/env bash
set -euo pipefail

gateway_controller="SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift"
wifi_controller="SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift"
sync_data="SunSmart/Common/Data/Node+SyncData.swift"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

grep -q "var supportsAPNConfiguration: Bool" "$gateway_controller" \
  || fail "GatewayViewController must expose an overridable APN capability."

grep -q "supportsAPNConfiguration ? baseSections : baseSections.filter" "$gateway_controller" \
  || fail "GatewayViewController sections must filter .apn when APN is unsupported."

grep -q "if supportsAPNConfiguration {" "$gateway_controller" \
  || fail "GatewayViewController copied information must omit APN when APN is unsupported."

grep -q "override var supportsAPNConfiguration: Bool" "$wifi_controller" \
  || fail "WiFiGatewayViewController must override APN capability."

grep -q "return false" "$wifi_controller" \
  || fail "WiFiGatewayViewController APN capability must be false."

grep -q "if !isWiFiGateway, let apn = gateway.apn" "$sync_data" \
  || fail "WiFi Gateway must not generate syncGatewaySIMAPN tasks."

echo "PASS: WiFi Gateway APN UI and save sync are gated."
